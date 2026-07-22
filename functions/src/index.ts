import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {onDocumentWritten, FirestoreEvent, Change, DocumentSnapshot} from "firebase-functions/v2/firestore";
import {onSchedule, ScheduledEvent} from "firebase-functions/v2/scheduler";
import * as crypto from "crypto";

admin.initializeApp();
const db = admin.firestore();

function hashPin(pin: string, salt: string): string {
  return crypto.createHash("sha256").update(`${pin}:${salt}`).digest("hex");
}

function generateResetCode(): string {
  return crypto.randomInt(100000, 999999).toString(); // 6-digit code
}

async function sendPinResetEmail(toEmail: string, code: string): Promise<void> {
  const user = process.env.SMTP_USER || "";
  const pass = process.env.SMTP_PASS || "";
  if (!user || !pass) {
    console.warn("SMTP credentials not configured in environment (SMTP_USER/SMTP_PASS). Reset email skipped.");
    return;
  }
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const nodemailer = require("nodemailer");
  const transporter = nodemailer.createTransport({
    host: "smtp.gmail.com",
    port: 587,
    secure: false,
    auth: {user, pass},
  });

  await transporter.sendMail({
    from: '"Inventra" <noreply@inventra.app>',
    to: toEmail,
    subject: "Your Inventra PIN reset code",
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 480px; margin: 0 auto;">
        <div style="background-color: #2E7D32; padding: 24px; border-radius: 10px 10px 0 0; text-align: center;">
          <h1 style="color: #fff; font-size: 20px; margin: 0;">INVENTRA</h1>
        </div>
        <div style="background-color: #f9f9f9; padding: 28px; border: 1px solid #e5e5e5; border-top: none; border-radius: 0 0 10px 10px;">
          <p style="font-size: 15px; color: #333;">Use this code to reset your Edit PIN:</p>
          <p style="font-size: 32px; font-weight: bold; letter-spacing: 6px; color: #2E7D32; text-align: center; margin: 20px 0;">${code}</p>
          <p style="font-size: 13px; color: #888;">This code expires in 15 minutes. If you didn't request this, you can safely ignore this email.</p>
        </div>
      </div>
    `,
  });
}

/**
 * Set the Edit PIN for the first time, or change it while already
 * authenticated with the current PIN.
 */
export const setEditPin = onCall(
  {enforceAppCheck: false},
  async (request: CallableRequest<any>) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated");
    const uid = request.auth.uid;
    const {newPin, currentPin} = request.data || {};

    if (!newPin || typeof newPin !== "string" || !/^\d{4}$/.test(newPin)) {
      throw new HttpsError("invalid-argument", "PIN must be exactly 4 digits");
    }

    await checkRateLimit(uid, "setEditPin", 5);

    const userRef = db.doc(`users/${uid}`);
    const userSnap = await userRef.get();
    const existingHash = userSnap.data()?.editPinHash as string | undefined;
    const existingSalt = userSnap.data()?.editPinSalt as string | undefined;

    // If a PIN already exists, the caller must prove they know it first.
    if (existingHash) {
      if (!currentPin || hashPin(currentPin, existingSalt || "") !== existingHash) {
        throw new HttpsError("permission-denied", "Current PIN is incorrect");
      }
    }

    const salt = crypto.randomBytes(16).toString("hex");
    await userRef.set({
      editPinHash: hashPin(newPin, salt),
      editPinSalt: salt,
      editPinResetCodeHash: admin.firestore.FieldValue.delete(),
      editPinResetExpiresAt: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {success: true};
  }
);

/**
 * Verify an entered PIN against the stored hash. Called every time the
 * Edit tab is unlocked — the client never reads the hash directly.
 */
export const verifyEditPin = onCall({enforceAppCheck: false}, async (request: CallableRequest<any>) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated");
  const uid = request.auth.uid;
  const {pin} = request.data || {};

  await checkRateLimit(uid, "verifyEditPin", 10);

  const userSnap = await db.doc(`users/${uid}`).get();
  const hash = userSnap.data()?.editPinHash as string | undefined;
  const salt = userSnap.data()?.editPinSalt as string | undefined;

  if (!hash) return {valid: false, hasPin: false};
  return {valid: hashPin(pin, salt || "") === hash, hasPin: true};
});

/**
 * Step 1 of forgot-PIN: emails a 6-digit reset code to the user's
 * verified account email. Replaces the old recovery-code system.
 */
export const requestEditPinReset = onCall(
  {enforceAppCheck: false},
  async (request: CallableRequest<any>) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated");
    const uid = request.auth.uid;

    await checkRateLimit(uid, "requestEditPinReset", 3);

    const userSnap = await db.doc(`users/${uid}`).get();
    const email = userSnap.data()?.email as string | undefined;
    if (!email) throw new HttpsError("failed-precondition", "No email on file");

    const code = generateResetCode();
    const codeSalt = crypto.randomBytes(16).toString("hex");
    const expiresAt = Date.now() + 15 * 60 * 1000; // 15 minutes

    await db.doc(`users/${uid}`).set({
      editPinResetCodeHash: hashPin(code, codeSalt),
      editPinResetCodeSalt: codeSalt,
      editPinResetExpiresAt: expiresAt,
    }, {merge: true});

    await sendPinResetEmail(email, code);

    // Return a masked email so the UI can show "Code sent to j***@gmail.com"
    const [local, domain] = email.split("@");
    const masked = `${local.slice(0, 1)}***@${domain}`;
    return {success: true, maskedEmail: masked};
  }
);

/**
 * Step 2 of forgot-PIN: verifies the emailed code and sets the new PIN.
 */
export const confirmEditPinReset = onCall({enforceAppCheck: false}, async (request: CallableRequest<any>) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated");
  const uid = request.auth.uid;
  const {code, newPin} = request.data || {};

  if (!newPin || !/^\d{4}$/.test(newPin)) {
    throw new HttpsError("invalid-argument", "PIN must be exactly 4 digits");
  }

  await checkRateLimit(uid, "confirmEditPinReset", 5);

  const userRef = db.doc(`users/${uid}`);
  const userSnap = await userRef.get();
  const data = userSnap.data() || {};
  const storedHash = data.editPinResetCodeHash as string | undefined;
  const storedSalt = data.editPinResetCodeSalt as string | undefined;
  const expiresAt = data.editPinResetExpiresAt as number | undefined;

  if (!storedHash || !expiresAt || Date.now() > expiresAt) {
    throw new HttpsError("failed-precondition", "Reset code has expired. Request a new one.");
  }
  if (hashPin(code || "", storedSalt || "") !== storedHash) {
    throw new HttpsError("permission-denied", "Incorrect reset code");
  }

  const newSalt = crypto.randomBytes(16).toString("hex");
  await userRef.set({
    editPinHash: hashPin(newPin, newSalt),
    editPinSalt: newSalt,
    editPinResetCodeHash: admin.firestore.FieldValue.delete(),
    editPinResetCodeSalt: admin.firestore.FieldValue.delete(),
    editPinResetExpiresAt: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  return {success: true};
});

// ── Tax threshold constants (Nigeria Tax Act 2025) ──
const SMALL_COMPANY_THRESHOLD = 100_000_000;
const APPROACHING_RATIO = 0.85;

// Allowed payment methods
const ALLOWED_PAYMENT_METHODS = ["cash", "card", "transfer", "pos", "credit"];
const ALLOWED_ROLES = ["owner", "manager", "cashier", "viewer"];

/**
 * Helper to check rate limiting / throttling.
 * Window: 1 minute. Limit: max calls per window.
 */
async function checkRateLimit(uid: string, action: string, limit: number = 30): Promise<void> {
  const now = Date.now();
  const windowKey = Math.floor(now / 60000);
  const ref = db.doc(`rate_limits/${uid}_${action}_${windowKey}`);
  
  await db.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    const count = snap.exists ? (snap.data()?.count || 0) : 0;
    if (count >= limit) {
      throw new HttpsError("resource-exhausted", `Rate limit exceeded for ${action}. Please try again shortly.`);
    }
    txn.set(ref, {count: count + 1, expiresAt: new Date(now + 120000)}, {merge: true});
  });
}

/**
 * Helper to verify shop membership & role from server-managed collection.
 */
async function verifyShopMember(
  uid: string,
  shopId: string,
  allowedRoles: string[]
): Promise<{role: string; name: string}> {
  const memberDoc = await db.doc(`shops/${shopId}/members/${uid}`).get();
  if (!memberDoc.exists || memberDoc.data()?.isActive !== true) {
    throw new HttpsError("permission-denied", "Not an active member of this shop");
  }

  const memberData = memberDoc.data()!;
  if (!allowedRoles.includes(memberData.role)) {
    throw new HttpsError("permission-denied", `Role '${memberData.role}' is not authorized for this operation`);
  }

  const userDoc = await db.collection("users").doc(uid).get();
  const name = userDoc.data()?.displayName || "Staff Member";

  return {role: memberData.role, name};
}

/**
 * Sends a push notification to every registered device for a shop.
 */
async function sendPushToShop(
  shopId: string,
  title: string,
  body: string,
  data: Record<string, string> = {}
): Promise<void> {
  const tokensSnap = await db.collection(`shops/${shopId}/fcmTokens`).get();
  if (tokensSnap.empty) return;

  const tokens = tokensSnap.docs.map((d) => d.id);
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {title, body},
    data,
    android: {priority: "high"},
    apns: {payload: {aps: {sound: "default"}}},
  });

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
    staleTokens.map((t) => db.doc(`shops/${shopId}/fcmTokens/${t}`).delete())
  );
}

/**
 * Atomically claims a one-per-year notification slot on shop settings.
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
 * Callable function to create a new shop and bootstrap owner membership.
 */
export const createShopAndOwner = onCall({enforceAppCheck: false}, async (request: CallableRequest<any>) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated");
  const uid = request.auth.uid;
  const {name, currency, address, phone} = request.data || {};

  if (!name || typeof name !== "string" || name.trim().length === 0 || name.length > 100) {
    throw new HttpsError("invalid-argument", "Invalid shop name");
  }

  await checkRateLimit(uid, "createShopAndOwner", 5);

  const shopRef = db.collection("shops").doc();
  const memberRef = db.doc(`shops/${shopRef.id}/members/${uid}`);
  const userRef = db.doc(`users/${uid}`);

  await db.runTransaction(async (txn) => {
    txn.set(shopRef, {
      name: name.trim(),
      currency: currency || "NGN",
      address: address || "",
      phone: phone || "",
      ownerId: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    txn.set(memberRef, {
      uid,
      role: "owner",
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: uid,
    });

    // Denormalized display state only
    txn.set(userRef, {
      shopId: shopRef.id,
      shopName: name.trim(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  return {shopId: shopRef.id, message: "Shop created successfully"};
});

/**
 * Callable function to manage shop members (owner only).
 */
export const manageShopMember = onCall({enforceAppCheck: false}, async (request: CallableRequest<any>) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated");
  const uid = request.auth.uid;
  const {shopId, targetUid, role, isActive} = request.data || {};

  if (!shopId || !targetUid) {
    throw new HttpsError("invalid-argument", "shopId and targetUid are required");
  }

  await verifyShopMember(uid, shopId, ["owner"]);
  await checkRateLimit(uid, "manageShopMember", 20);

  if (role && !ALLOWED_ROLES.includes(role)) {
    throw new HttpsError("invalid-argument", "Invalid role specified");
  }

  const memberRef = db.doc(`shops/${shopId}/members/${targetUid}`);

  await db.runTransaction(async (txn) => {
    const snap = await txn.get(memberRef);
    const updates: Record<string, any> = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: uid,
    };

    if (role) updates.role = role;
    if (typeof isActive === "boolean") updates.isActive = isActive;

    if (!snap.exists) {
      updates.uid = targetUid;
      updates.role = role || "viewer";
      updates.isActive = isActive ?? true;
      updates.createdAt = admin.firestore.FieldValue.serverTimestamp();
      updates.createdBy = uid;
      txn.set(memberRef, updates);
    } else {
      txn.update(memberRef, updates);
    }
  });

  return {success: true};
});

/**
 * Validate and execute stock deduction atomically (Sales POS).
 */
export const validateStockDeduction = onCall({enforceAppCheck: false}, async (request: CallableRequest<any>) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  const uid = request.auth.uid;
  const {shopId, items, paymentMethod, discount, note} = request.data || {};

  if (!shopId || typeof shopId !== "string" || !items || !Array.isArray(items) || items.length === 0) {
    throw new HttpsError("invalid-argument", "Missing or invalid required fields");
  }

  if (items.length > 50) {
    throw new HttpsError("invalid-argument", "Transaction exceeds max limit of 50 items");
  }

  const {name: userName} = await verifyShopMember(uid, shopId, ["owner", "manager", "cashier"]);
  await checkRateLimit(uid, "validateStockDeduction", 60);

  const cleanPaymentMethod = ALLOWED_PAYMENT_METHODS.includes(paymentMethod) ? paymentMethod : "cash";

  try {
    const result = await db.runTransaction(async (transaction: admin.firestore.Transaction) => {
      let subtotal = 0;
      const productUpdates: {ref: admin.firestore.DocumentReference; newQty: number; product: any; qty: number}[] = [];

      // Read all products first
      for (const item of items) {
        if (!item.productId || typeof item.productId !== "string") {
          throw new HttpsError("invalid-argument", "Invalid productId in item list");
        }

        const qty = Number(item.quantity);
        if (!Number.isInteger(qty) || qty <= 0 || qty > 10000) {
          throw new HttpsError("invalid-argument", `Invalid item quantity: ${item.quantity}`);
        }

        const productRef = db.doc(`shops/${shopId}/products/${item.productId}`);
        const productDoc = await transaction.get(productRef);

        if (!productDoc.exists) {
          throw new HttpsError("not-found", `Product ${item.productId} not found`);
        }

        const product = productDoc.data()!;
        if (product.isActive !== true) {
          throw new HttpsError("failed-precondition", `Product ${product.name} is not active`);
        }

        const currentQty = (product.quantity as number) || 0;
        if (currentQty < qty) {
          throw new HttpsError(
            "failed-precondition",
            `Insufficient stock for ${product.name}. Available: ${currentQty}, Requested: ${qty}`
          );
        }

        const unitPrice = (product.sellingPrice as number) || 0;
        subtotal += unitPrice * qty;

        productUpdates.push({
          ref: productRef,
          newQty: currentQty - qty,
          product,
          qty,
        });
      }

      // Validate discount
      const discountAmount = Number(discount) || 0;
      if (isNaN(discountAmount) || discountAmount < 0 || discountAmount > subtotal) {
        throw new HttpsError("invalid-argument", "Discount must be between 0 and subtotal");
      }

      const total = subtotal - discountAmount;
      const transactionRef = db.collection(`shops/${shopId}/transactions`).doc();

      const transactionData = {
        type: "sale",
        items: productUpdates.map((u) => ({
          productId: u.ref.id,
          productName: u.product.name,
          sku: u.product.sku || "",
          quantity: u.qty,
          unitPrice: u.product.sellingPrice,
          totalPrice: u.product.sellingPrice * u.qty,
        })),
        subtotal,
        discount: discountAmount,
        taxAmount: 0,
        total,
        paymentMethod: cleanPaymentMethod,
        status: "completed",
        note: (typeof note === "string" ? note.substring(0, 500) : null),
        createdBy: uid,
        createdByName: userName,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      transaction.set(transactionRef, transactionData);

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

      // Increment daily aggregate revenue
      const today = new Date().toISOString().split("T")[0];
      const aggregateRef = db.doc(`shops/${shopId}/analytics_snapshots/${today}`);
      transaction.set(aggregateRef, {
        date: today,
        totalSales: admin.firestore.FieldValue.increment(1),
        totalRevenue: admin.firestore.FieldValue.increment(total),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      return {transactionId: transactionRef.id, total};
    });

    return result;
  } catch (error: any) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message || "Transaction failed");
  }
});

/**
 * Callable function for restock operations (Owner/Manager only).
 */
export const processRestock = onCall({enforceAppCheck: false}, async (request: CallableRequest<any>) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated");
  const uid = request.auth.uid;
  const {shopId, productId, quantity, costPrice, supplier, note} = request.data || {};

  if (!shopId || !productId) {
    throw new HttpsError("invalid-argument", "shopId and productId are required");
  }

  const qty = Number(quantity);
  if (!Number.isInteger(qty) || qty <= 0 || qty > 100000) {
    throw new HttpsError("invalid-argument", "Restock quantity must be a positive integer");
  }

  const {name: userName} = await verifyShopMember(uid, shopId, ["owner", "manager"]);
  await checkRateLimit(uid, "processRestock", 30);

  const productRef = db.doc(`shops/${shopId}/products/${productId}`);

  return db.runTransaction(async (txn) => {
    const pSnap = await txn.get(productRef);
    if (!pSnap.exists) throw new HttpsError("not-found", "Product not found");

    const pData = pSnap.data()!;
    const currentQty = (pData.quantity as number) || 0;
    const newQty = currentQty + qty;

    const updates: Record<string, any> = {
      quantity: newQty,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (typeof costPrice === "number" && costPrice >= 0) {
      updates.costPrice = costPrice;
    }

    txn.update(productRef, updates);

    const movementRef = db.collection(`shops/${shopId}/stock_movements`).doc();
    txn.set(movementRef, {
      productId,
      productName: pData.name,
      type: "restock",
      quantityChange: qty,
      quantityBefore: currentQty,
      quantityAfter: newQty,
      supplier: supplier || null,
      note: note || null,
      userId: uid,
      userName,
      source: "restock",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {productId, newQuantity: newQty};
  });
});

/**
 * Callable function for stock adjustments (Owner/Manager only).
 */
export const processStockAdjustment = onCall({enforceAppCheck: false}, async (request: CallableRequest<any>) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated");
  const uid = request.auth.uid;
  const {shopId, productId, newQuantity, reason} = request.data || {};

  if (!shopId || !productId) {
    throw new HttpsError("invalid-argument", "shopId and productId are required");
  }

  const targetQty = Number(newQuantity);
  if (!Number.isInteger(targetQty) || targetQty < 0 || targetQty > 1000000) {
    throw new HttpsError("invalid-argument", "New quantity must be a non-negative integer");
  }

  const {name: userName} = await verifyShopMember(uid, shopId, ["owner", "manager"]);
  await checkRateLimit(uid, "processStockAdjustment", 30);

  const productRef = db.doc(`shops/${shopId}/products/${productId}`);

  return db.runTransaction(async (txn) => {
    const pSnap = await txn.get(productRef);
    if (!pSnap.exists) throw new HttpsError("not-found", "Product not found");

    const pData = pSnap.data()!;
    const currentQty = (pData.quantity as number) || 0;
    const diff = targetQty - currentQty;

    txn.update(productRef, {
      quantity: targetQty,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const movementRef = db.collection(`shops/${shopId}/stock_movements`).doc();
    txn.set(movementRef, {
      productId,
      productName: pData.name,
      type: "adjustment",
      quantityChange: diff,
      quantityBefore: currentQty,
      quantityAfter: targetQty,
      reason: reason || "Stock Count Adjustment",
      userId: uid,
      userName,
      source: "adjustment",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {productId, newQuantity: targetQty};
  });
});

/**
 * Callable function to update shop settings (Owner only).
 */
export const updateShopSettings = onCall({enforceAppCheck: false}, async (request: CallableRequest<any>) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated");
  const uid = request.auth.uid;
  const {shopId, settings} = request.data || {};

  if (!shopId || !settings || typeof settings !== "object") {
    throw new HttpsError("invalid-argument", "shopId and settings object are required");
  }

  await verifyShopMember(uid, shopId, ["owner"]);
  await checkRateLimit(uid, "updateShopSettings", 10);

  const allowedFields = ["currency", "lowStockThreshold", "expiryAlertDays", "enableExpiryAlerts", "taxRate", "receiptHeader"];
  const sanitized: Record<string, any> = {
    updatedBy: uid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  for (const key of Object.keys(settings)) {
    if (allowedFields.includes(key)) {
      sanitized[key] = settings[key];
    }
  }

  const settingsRef = db.doc(`shops/${shopId}/settings/config`);
  await settingsRef.set(sanitized, {merge: true});

  return {success: true};
});

/**
 * Check low stock on product write.
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
    const reorderLevel = (after.reorderLevel as number) || 5;
    const productName = after.name as string;

    const wasLow = before ? (before.quantity as number) <= ((before.reorderLevel as number) || 5) : false;
    const wasOut = before ? (before.quantity as number) <= 0 : false;

    const isOut = quantity <= 0;
    const isLow = quantity <= reorderLevel && quantity > 0;

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
 * Check annual revenue against Nigeria Tax Act 2025 small-company threshold.
 * Uses daily/monthly aggregates to avoid reading all yearly transactions on every write.
 */
export const checkTaxThreshold = onDocumentWritten(
  "shops/{shopId}/transactions/{transactionId}",
  async (event: FirestoreEvent<Change<DocumentSnapshot> | undefined, {shopId: string; transactionId: string}>) => {
    const after = event.data?.after?.data();
    if (!after || after.type !== "sale") return;

    const shopId = event.params.shopId;
    const year = new Date().getFullYear();

    // Query daily aggregate snapshots for the current year
    const snapshots = await db
      .collection(`shops/${shopId}/analytics_snapshots`)
      .where("date", ">=", `${year}-01-01`)
      .where("date", "<=", `${year}-12-31`)
      .get();

    const annualRevenue = snapshots.docs.reduce(
      (sum, doc) => sum + ((doc.data().totalRevenue as number) || 0),
      0
    );

    const settingsRef = db.doc(`shops/${shopId}/settings/config`);

    if (annualRevenue >= SMALL_COMPANY_THRESHOLD) {
      const claimed = await claimNotificationSlot(settingsRef, "taxThresholdNotified_exceeded", year);
      if (claimed) {
        await db.collection(`shops/${shopId}/notifications`).add({
          type: "tax_threshold",
          title: "Annual Revenue Milestone Reached",
          body: `Tracked revenue for ${year} has crossed ₦100,000,000.`,
          data: {},
          read: false,
          userId: null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await sendPushToShop(
          shopId,
          "📊 Annual Revenue Milestone Reached",
          "Your shop has crossed ₦100,000,000 in tracked revenue this year.",
          {type: "tax_threshold"}
        );
      }
    } else if (annualRevenue >= SMALL_COMPANY_THRESHOLD * APPROACHING_RATIO) {
      const claimed = await claimNotificationSlot(settingsRef, "taxThresholdNotified_approaching", year);
      if (claimed) {
        const remaining = SMALL_COMPANY_THRESHOLD - annualRevenue;
        await sendPushToShop(
          shopId,
          "📈 Approaching Small-Company Tax Threshold",
          `Your shop has recorded over ₦${(annualRevenue / 1_000_000).toFixed(1)}M in revenue this year — about ₦${(remaining / 1_000_000).toFixed(1)}M below the limit.`,
          {type: "tax_threshold_approaching"}
        );
      }
    }
  }
);

/**
 * Check for expiring products (daily at 06:00 UTC).
 */
export const checkExpiringProducts = onSchedule(
  {schedule: "every day 06:00", timeZone: "UTC"},
  async (_event: ScheduledEvent) => {
    const shopsSnapshot = await db.collection("shops").get();

    for (const shopDoc of shopsSnapshot.docs) {
      const shopId = shopDoc.id;
      const settingsDoc = await db.doc(`shops/${shopId}/settings/config`).get();
      const settings = settingsDoc.data();
      const alertDays = (settings?.expiryAlertDays as number) || 30;
      if (settings?.enableExpiryAlerts === false) continue;

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
          const daysUntilExpiry = Math.ceil((expiryDate.getTime() - Date.now()) / (1000 * 60 * 60 * 24));
          await db.collection(`shops/${shopId}/notifications`).add({
            type: "expiry_warning",
            title: "Expiry Warning",
            body: `${product.name} expires in ${daysUntilExpiry} day(s)`,
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
 * Update category product count on product changes.
 */
export const updateCategoryProductCount = onDocumentWritten(
  "shops/{shopId}/products/{productId}",
  async (event: FirestoreEvent<Change<DocumentSnapshot> | undefined, {shopId: string; productId: string}>) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    const shopId = event.params.shopId;

    const beforeCatId = before?.categoryId as string | null;
    const afterCatId = after?.categoryId as string | null;

    if (beforeCatId === afterCatId) return;

    const batch = db.batch();
    if (beforeCatId) {
      batch.update(db.doc(`shops/${shopId}/categories/${beforeCatId}`), {
        productCount: admin.firestore.FieldValue.increment(-1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    if (afterCatId) {
      batch.update(db.doc(`shops/${shopId}/categories/${afterCatId}`), {
        productCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
);

/**
 * Daily analytics aggregation.
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
        totalRevenue += tx.total || 0;

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

      const productsSnapshot = await db
        .collection(`shops/${shopId}/products`)
        .where("isActive", "==", true)
        .get();

      let lowStockCount = 0;
      let inventoryValue = 0;
      for (const pDoc of productsSnapshot.docs) {
        const p = pDoc.data();
        if ((p.quantity || 0) <= (p.reorderLevel || 5)) lowStockCount++;
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
  }
);
