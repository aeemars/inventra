import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../../core/cache/local_database.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/sync/sync_processor.dart';
import '../../../core/sync/operation_journal.dart';
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

  /// Finds uncompleted queued operations for the specified entity IDs to ensure dependent operations wait.
  List<String> _findPendingDependencies(String shopId, Iterable<String> entityIds) {
    if (!_localDb.isInitialized) return const [];
    final idSet = entityIds.toSet();
    return _localDb.syncQueueBox.values
        .where((i) =>
            i.shopId == shopId &&
            i.entityId != null &&
            idSet.contains(i.entityId) &&
            (i.status == SyncStatus.pending || i.status == SyncStatus.processing))
        .map((i) => i.localId)
        .toList();
  }

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
      shopId: shopId,
    );

    // 1. Save locally to Hive with tenant isolation
    await _localDb.scanHistoryBox
        .put(LocalDatabase.scopedKey(shopId, entryId), updatedEntry);

    // 2. Queue for remote sync
    final priorDeps = entry.matchedProductId != null
        ? _findPendingDependencies(shopId, [entry.matchedProductId!])
        : const <String>[];
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
      dependsOnOperationIds: priorDeps,
      dependsOnOperationId: priorDeps.isNotEmpty ? priorDeps.last : null,
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
        final list = _localDb.scanHistoryBox.values
            .where((e) => e.shopId == shopId || e.shopId.isEmpty)
            .toList();
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
        final entry = ScanHistoryEntry.fromFirestore(doc, shopId);
        await _localDb.scanHistoryBox
            .put(LocalDatabase.scopedKey(shopId, doc.id), entry);
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
    // 1. Verify local stock availability and tenant ownership for all items
    for (final item in items) {
      final pId = item['productId'] as String;
      final requestedQty = (item['quantity'] as num).toInt();
      final product = _localDb.getProduct(shopId, pId);
      final availableQty = product?.quantity ?? 0;

      if (product == null || availableQty < requestedQty) {
        throw InsufficientStockException(
          available: availableQty,
          requested: requestedQty,
        );
      }
    }

    final txId = const Uuid().v4();

    // 2. Delegate to OfflineOperationManager for staged crash-safe execution
    return await OfflineOperationManager.executeAtomicSale(
      shopId: shopId,
      operationId: txId,
      userId: userId,
      userName: userName,
      items: items,
      paymentMethod: paymentMethod,
      discount: discount,
      note: note,
      localDb: _localDb,
      syncProcessor: _syncProcessor,
    );
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
    final product = _localDb.getProduct(shopId, productId);
    final currentQty = product?.quantity ?? 0;
    final newQty = currentQty + quantity;

    if (product != null) {
      await _localDb.putProduct(
        shopId,
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
      shopId: shopId,
    );
    await _localDb.putStockMovement(shopId, movement);

    final priorDeps = _findPendingDependencies(shopId, [productId]);
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
      dependsOnOperationIds: priorDeps,
      dependsOnOperationId: priorDeps.isNotEmpty ? priorDeps.last : null,
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
    final product = _localDb.getProduct(shopId, productId);
    final currentQty = product?.quantity ?? 0;
    final newQty =
        (currentQty + quantityChange) < 0 ? 0 : (currentQty + quantityChange);

    if (product != null) {
      await _localDb.putProduct(
        shopId,
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
      shopId: shopId,
    );
    await _localDb.putStockMovement(shopId, movement);

    final priorDeps = _findPendingDependencies(shopId, [productId]);
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
      dependsOnOperationIds: priorDeps,
      dependsOnOperationId: priorDeps.isNotEmpty ? priorDeps.last : null,
    );

    if (_syncProcessor != null) {
      await _syncProcessor.enqueue(syncItem);
    } else {
      await _localDb.syncQueueBox.put(syncItem.localId, syncItem);
    }
  }
}
