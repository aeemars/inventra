import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {onDocumentWritten, FirestoreEvent, Change, DocumentSnapshot} from "firebase-functions/v2/firestore";
import {onSchedule, ScheduledEvent} from "firebase-functions/v2/scheduler";

admin.initializeApp();
const db = admin.firestore();

// ── Tax threshold constants (Nigeria Tax Act 2025) ──
const SMALL_COMPANY_THRESHOLD = 100_000_000;
const APPROACHING_RATIO = 0.85;

/**
 * Sends a push notification to every registered device for a shop,
 * pruning any tokens that have expired or been uninstalled.
 */
async function sendPushToShop(
  shopId: string,
  title: string,
  body: string,
  data: Record<string, string> = {}
): Promise<void> {
  const tokensSnap = await db
    .collection(`shops/${shopId}/fcmTokens`)
    .get();

  if (tokensSnap.empty) return;

  const tokens = tokensSnap.docs.map((d) => d.id);

  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {title, body},
    data,
    android: {priority: "high"},
    apns: {payload: {aps: {sound: "default"}}},
  });

  // Prune invalid tokens (uninstalled app, expired token, etc.)
  const staleTokens: string[] = [];
  response.responses.forEach((res, i) => {
    if (
      !res.success &&
      (res.error?.code === "messaging/registration-token-not-registered" ||
        res.error?.code === "messaging/invalid-registration-token")
    ) {
      staleTokens.push(tokens[i]);
    }
  });

  await Promise.all(
    staleTokens.map((t) =>
      db.doc(`shops/${shopId}/fcmTokens/${t}`).delete()
    )
  );
}

/**
 * Atomically claims a one-per-year notification slot on the shop's
 * settings document, so concurrent writes from multiple staff devices
 * never trigger the same alert twice.
 */
async function claimNotificationSlot(
  settingsRef: admin.firestore.DocumentReference,
  fieldName: string,
  year: number
): Promise<boolean> {
  return db.runTransaction(async (txn) => {
    const snap = await txn.get(settingsRef);
    const alreadyNotifiedYear = snap.data()?.[fieldName] as number | undefined;
    if (alreadyNotifiedYear === year) return false;
    txn.set(settingsRef, {[fieldName]: year}, {merge: true});
    return true;
  });
}

/**
 * Validate and execute stock deduction atomically.
 * Prevents overselling via Firestore transaction.
 */
export const validateStockDeduction = onCall(async (request: CallableRequest<any>) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  const {shopId, items, paymentMethod, discount, note} = request.data;

  if (!shopId || !items || !Array.isArray(items) || items.length === 0) {
    throw new HttpsError("invalid-argument", "Missing required fields");
  }

  const uid = request.auth.uid;
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists || userDoc.data()?.shopId !== shopId) {
    throw new HttpsError("permission-denied", "Not authorized for this shop");
  }

  const userName = userDoc.data()?.displayName || "Unknown";

  try {
    const result = await db.runTransaction(async (transaction: admin.firestore.Transaction) => {
      let subtotal = 0;
      const productUpdates: {ref: admin.firestore.DocumentReference; newQty: number; product: any; qty: number}[] = [];

      // Phase 1: Read all products and validate stock
      for (const item of items) {
        const productRef = db.doc(`shops/${shopId}/products/${item.productId}`);
        const productDoc = await transaction.get(productRef);

        if (!productDoc.exists) {
          throw new HttpsError("not-found", `Product ${item.productId} not found`);
        }

        const product = productDoc.data()!;
        const currentQty = product.quantity as number;

        if (currentQty < item.quantity) {
          throw new HttpsError(
            "failed-precondition",
            `Insufficient stock for ${product.name}. Available: ${currentQty}, Requested: ${item.quantity}`
          );
        }

        const itemTotal = (product.sellingPrice as number) * item.quantity;
        subtotal += itemTotal;

        productUpdates.push({
          ref: productRef,
          newQty: currentQty - item.quantity,
          product,
          qty: item.quantity,
        });
      }

      // Calculate totals
      const discountAmount = discount || 0;
      const total = subtotal - discountAmount;

      // Phase 2: Write all updates
      const transactionRef = db.collection(`shops/${shopId}/transactions`).doc();

      // Create transaction record
      const transactionData = {
        type: "sale",
        items: productUpdates.map((u) => ({
          productId: u.ref.id,
          productName: u.product.name,
          sku: u.product.sku,
          quantity: u.qty,
          unitPrice: u.product.sellingPrice,
          totalPrice: u.product.sellingPrice * u.qty,
        })),
        subtotal,
        discount: discountAmount,
        taxAmount: 0,
        total,
        paymentMethod: paymentMethod || "cash",
        status: "completed",
        note: note || null,
        createdBy: uid,
        createdByName: userName,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      transaction.set(transactionRef, transactionData);

      // Update each product and create stock movement
      for (const update of productUpdates) {
        transaction.update(update.ref, {
          quantity: update.newQty,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const movementRef = db.collection(`shops/${shopId}/stock_movements`).doc();
        transaction.set(movementRef, {
          productId: update.ref.id,
          productName: update.product.name,
          type: "sale",
          quantityChange: -update.qty,
          quantityBefore: update.product.quantity,
          quantityAfter: update.newQty,
          reference: transactionRef.id,
          userId: uid,
          userName: userName,
          source: "pos",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return {transactionId: transactionRef.id, total};
    });

    return result;
  } catch (error: any) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message || "Transaction failed");
  }
});

/**
 * Check low stock on product write — only fires on genuine transitions
 * into a low/out-of-stock state, and sends a real FCM push.
 */
export const checkLowStock = onDocumentWritten(
  "shops/{shopId}/products/{productId}",
  async (event: FirestoreEvent<Change<DocumentSnapshot> | undefined, {shopId: string; productId: string}>) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return;

    const shopId = event.params.shopId;
    const productId = event.params.productId;
    const quantity = after.quantity as number;
    const reorderLevel = after.reorderLevel as number;
    const productName = after.name as string;

    const wasLow = before
      ? (before.quantity as number) <= (before.reorderLevel as number)
      : false;
    const wasOut = before ? (before.quantity as number) <= 0 : false;

    const isOut = quantity <= 0;
    const isLow = quantity <= reorderLevel && quantity > 0;

    // Only act on a genuine transition INTO a low/out state — not on
    // every write while the product remains low, and not when it's
    // restocked back to normal.
    if (isOut && !wasOut) {
      await db.collection(`shops/${shopId}/notifications`).add({
        type: "out_of_stock",
        title: "Out of Stock!",
        body: `${productName} is completely out of stock`,
        data: {productId},
        read: false,
        userId: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await sendPushToShop(
        shopId,
        "🚨 Out of Stock",
        `${productName} has zero units left. Restock immediately.`,
        {type: "out_of_stock", productId}
      );
    } else if (isLow && !wasLow) {
      await db.collection(`shops/${shopId}/notifications`).add({
        type: "low_stock",
        title: "Low Stock Alert",
        body: `${productName} is running low (${quantity} remaining)`,
        data: {productId},
        read: false,
        userId: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await sendPushToShop(
        shopId,
        "⚠️ Low Stock",
        `${productName} is running low — only ${quantity} remaining.`,
        {type: "low_stock", productId}
      );
    }
  }
);

/**
 * Check annual revenue against the Nigeria Tax Act 2025 small-company
 * threshold on every sale transaction write. Sends FCM push at 85%
 * approaching and 100% exceeded.
 */
export const checkTaxThreshold = onDocumentWritten(
  "shops/{shopId}/transactions/{transactionId}",
  async (event: FirestoreEvent<Change<DocumentSnapshot> | undefined, {shopId: string; transactionId: string}>) => {
    const after = event.data?.after?.data();
    if (!after || after.type !== "sale") return;

    const shopId = event.params.shopId;
    const year = new Date().getFullYear();
    const yearStart = new Date(year, 0, 1);

    const txSnap = await db
      .collection(`shops/${shopId}/transactions`)
      .where("type", "==", "sale")
      .where("createdAt", ">=", yearStart)
      .get();

    const annualRevenue = txSnap.docs.reduce(
      (sum, doc) => sum + ((doc.data().total as number) || 0),
      0
    );

    const settingsRef = db.doc(`shops/${shopId}/settings/config`);

    if (annualRevenue >= SMALL_COMPANY_THRESHOLD) {
      const claimed = await claimNotificationSlot(
        settingsRef, "taxThresholdNotified_exceeded", year
      );
      if (claimed) {
        await db.collection(`shops/${shopId}/notifications`).add({
          type: "tax_threshold",
          title: "Annual Revenue Milestone Reached",
          body: `Tracked revenue for ${year} has crossed ₦100,000,000. This may affect your small-company tax exemption status under the Nigeria Tax Act 2025. Consider consulting a tax professional about CIT registration and filing.`,
          data: {},
          read: false,
          userId: null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await sendPushToShop(
          shopId,
          "📊 Annual Revenue Milestone Reached",
          "Your shop has crossed ₦100,000,000 in tracked revenue this year — you may no longer qualify for small-company tax exemption. Consider speaking with a tax professional.",
          {type: "tax_threshold"}
        );
      }
    } else if (annualRevenue >= SMALL_COMPANY_THRESHOLD * APPROACHING_RATIO) {
      const claimed = await claimNotificationSlot(
        settingsRef, "taxThresholdNotified_approaching", year
      );
      if (claimed) {
        const remaining = SMALL_COMPANY_THRESHOLD - annualRevenue;
        await sendPushToShop(
          shopId,
          "📈 Approaching the Small-Company Tax Threshold",
          `Your shop has recorded over ₦${(annualRevenue / 1_000_000).toFixed(1)}M in revenue this year — about ₦${(remaining / 1_000_000).toFixed(1)}M below the ₦100M small-company exemption limit.`,
          {type: "tax_threshold_approaching"}
        );
      }
    }
  }
);

/**
 * Check for products nearing expiry (runs daily at 06:00 UTC).
 */
export const checkExpiringProducts = onSchedule(
  {schedule: "every day 06:00", timeZone: "UTC"},
  async (_event: ScheduledEvent) => {
    const shopsSnapshot = await db.collection("shops").get();

    for (const shopDoc of shopsSnapshot.docs) {
      const shopId = shopDoc.id;

      // Get shop settings for expiry alert configuration
      const settingsDoc = await db.doc(`shops/${shopId}/settings/config`).get();
      const settings = settingsDoc.data();
      const alertDays = (settings?.expiryAlertDays as number) || 30;
      const enableExpiryAlerts = settings?.enableExpiryAlerts !== false;

      if (!enableExpiryAlerts) continue;

      const alertDate = new Date();
      alertDate.setDate(alertDate.getDate() + alertDays);

      const productsSnapshot = await db
        .collection(`shops/${shopId}/products`)
        .where("isActive", "==", true)
        .get();

      for (const productDoc of productsSnapshot.docs) {
        const product = productDoc.data();
        const expiryDate = product.expiryDate?.toDate?.();

        if (!expiryDate) continue;

        if (expiryDate <= alertDate && expiryDate > new Date()) {
          const daysUntilExpiry = Math.ceil(
            (expiryDate.getTime() - Date.now()) / (1000 * 60 * 60 * 24)
          );

          await db.collection(`shops/${shopId}/notifications`).add({
            type: "expiry_warning",
            title: "Expiry Warning",
            body: `${product.name} expires in ${daysUntilExpiry} day${daysUntilExpiry === 1 ? "" : "s"}`,
            data: {productId: productDoc.id, expiryDate: expiryDate.toISOString()},
            read: false,
            userId: null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } else if (expiryDate <= new Date()) {
          await db.collection(`shops/${shopId}/notifications`).add({
            type: "expiry_warning",
            title: "Product Expired!",
            body: `${product.name} has expired`,
            data: {productId: productDoc.id, expiryDate: expiryDate.toISOString()},
            read: false,
            userId: null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }
    }
  }
);

/**
 * Update category product count when a product is created, updated, or deleted.
 */
export const updateCategoryProductCount = onDocumentWritten(
  "shops/{shopId}/products/{productId}",
  async (event: FirestoreEvent<Change<DocumentSnapshot> | undefined, {shopId: string; productId: string}>) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    const shopId = event.params.shopId;

    const beforeCategoryId = before?.categoryId as string | null;
    const afterCategoryId = after?.categoryId as string | null;

    // If category didn't change, nothing to do
    if (beforeCategoryId === afterCategoryId) return;

    const batch = db.batch();

    // Decrement old category count
    if (beforeCategoryId) {
      const oldCatRef = db.doc(`shops/${shopId}/categories/${beforeCategoryId}`);
      batch.update(oldCatRef, {
        productCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Increment new category count
    if (afterCategoryId) {
      const newCatRef = db.doc(`shops/${shopId}/categories/${afterCategoryId}`);
      batch.update(newCatRef, {
        productCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }
);

/**
 * Daily analytics aggregation (runs at midnight UTC).
 */
export const aggregateDailySales = onSchedule(
  {schedule: "every day 00:00", timeZone: "UTC"},
  async (_event: ScheduledEvent) => {
  const shopsSnapshot = await db.collection("shops").get();

  for (const shopDoc of shopsSnapshot.docs) {
    const shopId = shopDoc.id;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    const transactionsSnapshot = await db
      .collection(`shops/${shopId}/transactions`)
      .where("createdAt", ">=", today)
      .where("createdAt", "<", tomorrow)
      .where("status", "==", "completed")
      .get();

    let totalSales = 0;
    let totalRevenue = 0;
    const productSales: Record<string, {name: string; qty: number; revenue: number}> = {};

    for (const txDoc of transactionsSnapshot.docs) {
      const tx = txDoc.data();
      totalSales++;
      totalRevenue += tx.total;

      for (const item of tx.items || []) {
        if (!productSales[item.productId]) {
          productSales[item.productId] = {name: item.productName, qty: 0, revenue: 0};
        }
        productSales[item.productId].qty += item.quantity;
        productSales[item.productId].revenue += item.totalPrice;
      }
    }

    const topProducts = Object.entries(productSales)
      .sort(([, a], [, b]) => b.revenue - a.revenue)
      .slice(0, 10)
      .map(([id, data]) => ({productId: id, ...data}));

    // Get low stock count and inventory value
    const productsSnapshot = await db
      .collection(`shops/${shopId}/products`)
      .where("isActive", "==", true)
      .get();

    let lowStockCount = 0;
    let inventoryValue = 0;
    for (const pDoc of productsSnapshot.docs) {
      const p = pDoc.data();
      if (p.quantity <= p.reorderLevel) lowStockCount++;
      inventoryValue += (p.costPrice || 0) * (p.quantity || 0);
    }

    const dateKey = today.toISOString().split("T")[0];
    await db.doc(`shops/${shopId}/analytics_snapshots/${dateKey}`).set({
      date: today,
      totalSales,
      totalRevenue,
      totalTransactions: totalSales,
      topProducts,
      inventoryValue,
      lowStockCount,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
});
