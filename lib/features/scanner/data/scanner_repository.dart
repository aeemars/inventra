import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../../core/cache/local_database.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/sync/sync_processor.dart';
import '../../../shared/models/scan_history_entry.dart';
import '../../../shared/models/stock_movement.dart';

/// Exception thrown when a sale would exceed available stock
class InsufficientStockException implements Exception {
  final int available;
  final int requested;

  const InsufficientStockException({
    required this.available,
    required this.requested,
  });

  @override
  String toString() =>
      'Insufficient stock. Available: $available, Requested: $requested';
}

class ScannerRepository {
  final FirebaseFirestore? _firestore;
  final LocalDatabase _localDb;
  final SyncProcessor? _syncProcessor;

  FirebaseFirestore get _firestoreInstance =>
      _firestore ?? FirebaseFirestore.instance;

  StreamSubscription? _remoteScanHistorySub;
  String? _listeningShopId;

  ScannerRepository({
    FirebaseFirestore? firestore,
    LocalDatabase? localDb,
    SyncProcessor? syncProcessor,
  })  : _firestore = firestore,
        _localDb = localDb ?? LocalDatabase.instance,
        _syncProcessor = syncProcessor;

  // ── Scan History ──

  Future<void> saveScanEntry(String shopId, ScanHistoryEntry entry) async {
    final entryId = entry.id.isEmpty ? const Uuid().v4() : entry.id;
    final updatedEntry = ScanHistoryEntry(
      id: entryId,
      barcodeValue: entry.barcodeValue,
      matchedProductId: entry.matchedProductId,
      matchedProductName: entry.matchedProductName,
      status: entry.status,
      scanIntent: entry.scanIntent,
      scannedBy: entry.scannedBy,
      scannedByName: entry.scannedByName,
      timestamp: entry.timestamp,
    );

    // 1. Save locally to Hive
    await _localDb.scanHistoryBox.put(entryId, updatedEntry);

    // 2. Queue for remote sync
    final syncItem = SyncQueueItem(
      localId: const Uuid().v4(),
      shopId: shopId,
      userId: entry.scannedBy,
      operationType: SyncOperationType.createScan,
      entityType: 'scan',
      entityId: entryId,
      payload: updatedEntry.toFirestore(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    if (_syncProcessor != null) {
      await _syncProcessor.enqueue(syncItem);
    } else {
      await _localDb.syncQueueBox.put(syncItem.localId, syncItem);
    }
  }

  Stream<List<ScanHistoryEntry>> watchScanHistory(String shopId) {
    _attachRemoteScanListener(shopId);

    return Stream<List<ScanHistoryEntry>>.multi((controller) {
      void emitLocal() {
        if (!_localDb.isInitialized) {
          controller.add([]);
          return;
        }
        final list = _localDb.scanHistoryBox.values.toList();
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        controller.add(list.take(200).toList());
      }

      emitLocal();
      final sub = _localDb.scanHistoryBox.watch().listen((_) => emitLocal());
      controller.onCancel = () => sub.cancel();
    });
  }

  void _attachRemoteScanListener(String shopId) {
    if (_listeningShopId == shopId) return;
    _listeningShopId = shopId;

    _remoteScanHistorySub?.cancel();
    _remoteScanHistorySub = _firestoreInstance
        .collection(FirestorePaths.scanHistory(shopId))
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .listen((snapshot) async {
      for (final doc in snapshot.docs) {
        final entry = ScanHistoryEntry.fromFirestore(doc);
        await _localDb.scanHistoryBox.put(doc.id, entry);
      }
    }, onError: (_) {});
  }

  // ── Sale (Local-first atomic stock deduction + queued server operation) ──

  /// Performs a local-first single item sale.
  /// Returns the transaction ID immediately.
  Future<String> performSale({
    required String shopId,
    required String productId,
    required String productName,
    required String productSku,
    required double unitPrice,
    required int quantity,
    required String userId,
    required String userName,
  }) async {
    return performMultiItemSale(
      shopId: shopId,
      items: [
        {
          'productId': productId,
          'productName': productName,
          'sku': productSku,
          'quantity': quantity,
          'unitPrice': unitPrice,
        }
      ],
      userId: userId,
      userName: userName,
    );
  }

  /// Performs an atomic multi-item sale local-first.
  /// Deducts local stock immediately, records local transaction and stock movements,
  /// and queues an idempotent sync operation.
  Future<String> performMultiItemSale({
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String userId,
    required String userName,
    String paymentMethod = 'cash',
    double discount = 0.0,
    String? note,
  }) async {
    final now = DateTime.now();

    // 1. Verify local stock availability for all items
    for (final item in items) {
      final pId = item['productId'] as String;
      final requestedQty = (item['quantity'] as num).toInt();
      final product = _localDb.productsBox.get(pId);
      final availableQty = product?.quantity ?? 0;

      if (availableQty < requestedQty) {
        throw InsufficientStockException(
          available: availableQty,
          requested: requestedQty,
        );
      }
    }

    // 2. Deduct local stock and generate line items
    double subtotal = 0;
    final saleItems = <SaleItem>[];
    final txId = const Uuid().v4();

    for (final item in items) {
      final pId = item['productId'] as String;
      final qty = (item['quantity'] as num).toInt();
      final product = _localDb.productsBox.get(pId)!;
      final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? product.sellingPrice;
      final lineTotal = unitPrice * qty;
      subtotal += lineTotal;

      // Update local product stock
      final newQty = product.quantity - qty;
      await _localDb.productsBox.put(
        pId,
        product.copyWith(quantity: newQty, updatedAt: now),
      );

      // Record local stock movement
      final movementId = const Uuid().v4();
      final movement = StockMovement(
        id: movementId,
        productId: pId,
        productName: product.name,
        type: 'sale',
        quantityChange: -qty,
        quantityBefore: product.quantity,
        quantityAfter: newQty,
        reference: txId,
        userId: userId,
        userName: userName,
        source: 'pos',
        createdAt: now,
      );
      await _localDb.stockMovementsBox.put(movementId, movement);

      saleItems.add(SaleItem(
        productId: pId,
        productName: product.name,
        sku: product.sku,
        quantity: qty,
        unitPrice: unitPrice,
        totalPrice: lineTotal,
      ));
    }

    final total = subtotal - discount;

    // 3. Record local SaleTransaction
    final transaction = SaleTransaction(
      id: txId,
      type: 'sale',
      items: saleItems,
      subtotal: subtotal,
      discount: discount,
      taxAmount: 0,
      total: total,
      paymentMethod: paymentMethod,
      status: 'completed',
      note: note,
      createdBy: userId,
      createdByName: userName,
      createdAt: now,
    );
    await _localDb.salesTransactionsBox.put(txId, transaction);

    // 4. Enqueue idempotent createSale sync operation
    final syncItem = SyncQueueItem(
      localId: txId, // Stable operationId
      shopId: shopId,
      userId: userId,
      operationType: SyncOperationType.createSale,
      entityType: 'sale',
      entityId: txId,
      payload: {
        'items': items,
        'paymentMethod': paymentMethod,
        'discount': discount,
        'note': note,
      },
      createdAt: now,
      updatedAt: now,
    );

    if (_syncProcessor != null) {
      await _syncProcessor.enqueue(syncItem);
    } else {
      await _localDb.syncQueueBox.put(syncItem.localId, syncItem);
    }

    return txId;
  }

  // ── Restock (Local-first + queued operation) ──

  Future<void> performRestock({
    required String shopId,
    required String productId,
    required String productName,
    required int quantity,
    required String userId,
    required String userName,
    String? note,
    String? supplier,
  }) async {
    final now = DateTime.now();
    final product = _localDb.productsBox.get(productId);
    final currentQty = product?.quantity ?? 0;
    final newQty = currentQty + quantity;

    if (product != null) {
      await _localDb.productsBox.put(
        productId,
        product.copyWith(quantity: newQty, updatedAt: now),
      );
    }

    final movementId = const Uuid().v4();
    final movement = StockMovement(
      id: movementId,
      productId: productId,
      productName: productName,
      type: 'restock',
      quantityChange: quantity,
      quantityBefore: currentQty,
      quantityAfter: newQty,
      reference: null,
      userId: userId,
      userName: userName,
      source: 'restock',
      createdAt: now,
    );
    await _localDb.stockMovementsBox.put(movementId, movement);

    final syncItem = SyncQueueItem(
      localId: const Uuid().v4(),
      shopId: shopId,
      userId: userId,
      operationType: SyncOperationType.restock,
      entityType: 'product',
      entityId: productId,
      payload: {
        'quantity': quantity,
        'note': note,
        'supplier': supplier,
      },
      createdAt: now,
      updatedAt: now,
    );

    if (_syncProcessor != null) {
      await _syncProcessor.enqueue(syncItem);
    } else {
      await _localDb.syncQueueBox.put(syncItem.localId, syncItem);
    }
  }

  // ── Stock Adjustment (Local-first + queued operation) ──

  Future<void> performAdjustment({
    required String shopId,
    required String productId,
    required String productName,
    required int quantityChange,
    required String userId,
    required String userName,
    String? reason,
  }) async {
    final now = DateTime.now();
    final product = _localDb.productsBox.get(productId);
    final currentQty = product?.quantity ?? 0;
    final newQty = (currentQty + quantityChange) < 0 ? 0 : (currentQty + quantityChange);

    if (product != null) {
      await _localDb.productsBox.put(
        productId,
        product.copyWith(quantity: newQty, updatedAt: now),
      );
    }

    final movementId = const Uuid().v4();
    final movement = StockMovement(
      id: movementId,
      productId: productId,
      productName: productName,
      type: 'adjustment',
      quantityChange: quantityChange,
      quantityBefore: currentQty,
      quantityAfter: newQty,
      reference: null,
      userId: userId,
      userName: userName,
      source: 'adjustment',
      createdAt: now,
    );
    await _localDb.stockMovementsBox.put(movementId, movement);

    final syncItem = SyncQueueItem(
      localId: const Uuid().v4(),
      shopId: shopId,
      userId: userId,
      operationType: SyncOperationType.stockAdjustment,
      entityType: 'product',
      entityId: productId,
      payload: {
        'quantityChange': quantityChange,
        'newQuantity': newQty,
        'reason': reason,
      },
      createdAt: now,
      updatedAt: now,
    );

    if (_syncProcessor != null) {
      await _syncProcessor.enqueue(syncItem);
    } else {
      await _localDb.syncQueueBox.put(syncItem.localId, syncItem);
    }
  }
}
