import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:uuid/uuid.dart';
import '../../../../core/cache/local_database.dart';
import '../../../../core/connectivity/connectivity_service.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/sync/sync_models.dart';
import '../../../../core/sync/sync_processor.dart';
import '../../../../shared/models/stock_movement.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/product_repository.dart';
import '../models/product_model.dart';

/// True offline-first implementation of ProductRepository.
/// Reads and writes immediately to local Hive storage, queuing server mutations
/// for asynchronous idempotent synchronization.
class OfflineProductRepository implements ProductRepository {
  final LocalDatabase _localDb;
  final SyncProcessor _syncProcessor;
  final FirebaseFirestore? _firestore;
  final ConnectivityService _connectivity;

  FirebaseFirestore get _firestoreInstance =>
      _firestore ?? FirebaseFirestore.instance;

  StreamSubscription? _remoteProductsSub;
  StreamSubscription? _remoteCategoriesSub;
  String? _listeningShopId;

  OfflineProductRepository({
    LocalDatabase? localDb,
    SyncProcessor? syncProcessor,
    FirebaseFirestore? firestore,
    ConnectivityService? connectivity,
  })  : _localDb = localDb ?? LocalDatabase.instance,
        _syncProcessor = syncProcessor ??
            SyncProcessor(
              localDb: localDb ?? LocalDatabase.instance,
              connectivity: connectivity ?? ConnectivityService(),
            ),
        _firestore = firestore,
        _connectivity = connectivity ?? ConnectivityService();

  String _cleanLookup(String value) => value.trim();

  String _normalizedLookup(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();

  /// Collects IDs of uncompleted queued operations for an entity to establish deterministic dependency chains.
  List<String> _findPendingOperationIds(String shopId, String entityId) {
    if (!_localDb.isInitialized) return const [];
    return _localDb.syncQueueBox.values
        .where((i) =>
            i.shopId == shopId &&
            i.entityId == entityId &&
            (i.status == SyncStatus.pending || i.status == SyncStatus.processing))
        .map((i) => i.localId)
        .toList();
  }

  // ── Products ──

  @override
  Stream<List<Product>> watchProducts(String shopId) {
    _attachRemoteListeners(shopId);

    // Stream from local Hive box scoped strictly to active shop
    return Stream<List<Product>>.multi((controller) {
      void emitLocal() {
        if (!_localDb.isInitialized) {
          controller.add([]);
          return;
        }
        final list = _localDb.getProducts(shopId, activeOnly: true);
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        controller.add(list);
      }

      emitLocal();
      final sub = _localDb.productsBox.watch().listen((_) => emitLocal());
      controller.onCancel = () => sub.cancel();
    });
  }

  void _attachRemoteListeners(String shopId) {
    if (_listeningShopId == shopId) return;
    _listeningShopId = shopId;

    _remoteProductsSub?.cancel();
    try {
      _remoteProductsSub = _firestoreInstance
          .collection(FirestorePaths.products(shopId))
          .snapshots()
          .listen((snapshot) async {
        final pendingProductOps = _localDb.syncQueueBox.values
            .where((i) => i.shopId == shopId && i.entityType == 'product')
            .map((i) => i.entityId)
            .toSet();

        for (final change in snapshot.docChanges) {
          final docId = change.doc.id;
          // Do not overwrite local changes if an operation is pending in queue
          if (pendingProductOps.contains(docId)) continue;

          if (change.type == DocumentChangeType.removed) {
            await _localDb.deleteProduct(shopId, docId);
          } else {
            final product =
                ProductModel.fromFirestore(change.doc, shopId).toEntity(shopId);
            await _localDb.putProduct(shopId, product);
          }
        }
      }, onError: (e) {
        debugPrint('⚠️ Remote products listener warning (offline): $e');
      });
    } catch (e) {
      debugPrint('⚠️ [OFFLINE REPO] Could not attach products remote listener: $e');
    }

    _remoteCategoriesSub?.cancel();
    try {
      _remoteCategoriesSub = _firestoreInstance
          .collection(FirestorePaths.categories(shopId))
          .snapshots()
          .listen((snapshot) async {
        for (final change in snapshot.docChanges) {
          final docId = change.doc.id;
          if (change.type == DocumentChangeType.removed) {
            await _localDb.deleteCategory(shopId, docId);
          } else {
            final data = change.doc.data();
            if (data != null) {
              final category = Category(
                id: docId,
                name: data['name'] as String? ?? '',
                description: data['description'] as String?,
                productCount: (data['productCount'] as num?)?.toInt() ?? 0,
                createdAt:
                    (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                updatedAt:
                    (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                shopId: shopId,
              );
              await _localDb.putCategory(shopId, category);
            }
          }
        }
      }, onError: (e) {
        debugPrint('⚠️ Remote categories listener warning (offline): $e');
      });
    } catch (e) {
      debugPrint('⚠️ [OFFLINE REPO] Could not attach categories remote listener: $e');
    }
  }

  @override
  Future<Product?> getProduct(String shopId, String productId) async {
    return _localDb.getProduct(shopId, productId);
  }

  @override
  Future<Product?> findByBarcode(String shopId, String barcode) async {
    final cleaned = _cleanLookup(barcode);
    if (cleaned.isEmpty) return null;

    final candidates = <String>{cleaned};
    if (cleaned.length == 13 && cleaned.startsWith('0')) {
      candidates.add(cleaned.substring(1));
    }
    if (cleaned.length == 12) {
      candidates.add('0$cleaned');
    }

    final allProducts = _localDb.productsBox.values.where(
        (p) => (p.shopId == shopId || p.shopId.isEmpty) && p.isActive);

    // 1. Exact match on barcode or sku
    for (final candidate in candidates) {
      for (final p in allProducts) {
        if (p.barcode == candidate || p.sku == candidate) {
          return p;
        }
      }
    }

    // 2. Normalized match
    final normalizedInput = _normalizedLookup(cleaned);
    if (normalizedInput.isEmpty) return null;

    for (final p in allProducts) {
      final normalizedSku = _normalizedLookup(p.sku);
      final normalizedBarcode =
          p.barcode == null ? '' : _normalizedLookup(p.barcode!);
      if (normalizedInput == normalizedSku ||
          (normalizedBarcode.isNotEmpty &&
              normalizedInput == normalizedBarcode)) {
        return p;
      }
    }

    return null;
  }

  @override
  Future<Product> addProduct(String shopId, Product product) async {
    final now = DateTime.now();
    // Stable UUID used for both local storage and Firestore doc ID
    final id = product.id.trim().isEmpty ? const Uuid().v4() : product.id;

    final newProduct = product.copyWith(
      id: id,
      shopId: shopId,
      createdAt: product.createdAt,
      updatedAt: now,
    );

    // 1. Save immediately to local Hive box with tenant isolation
    await _localDb.putProduct(shopId, newProduct);

    // 2. Queue sync operation
    final syncItem = SyncQueueItem(
      localId: const Uuid().v4(),
      shopId: shopId,
      userId: product.createdBy,
      operationType: SyncOperationType.createProduct,
      entityType: 'product',
      entityId: id,
      payload: ProductModel.fromEntity(newProduct).toFirestore(),
      createdAt: now,
      updatedAt: now,
    );
    await _syncProcessor.enqueue(syncItem);

    return newProduct;
  }

  @override
  Future<void> updateProduct(String shopId, Product product) async {
    final now = DateTime.now();
    final updated = product.copyWith(shopId: shopId, updatedAt: now);

    // 1. Save immediately to local Hive box with tenant isolation
    await _localDb.putProduct(shopId, updated);

    // 2. Queue sync operation with dependencies on any prior uncompleted operations
    final priorDeps = _findPendingOperationIds(shopId, product.id);
    final syncItem = SyncQueueItem(
      localId: const Uuid().v4(),
      shopId: shopId,
      userId: product.updatedBy,
      operationType: SyncOperationType.updateProduct,
      entityType: 'product',
      entityId: product.id,
      payload: ProductModel.fromEntity(updated).toFirestore(),
      createdAt: now,
      updatedAt: now,
      dependsOnOperationIds: priorDeps,
      dependsOnOperationId: priorDeps.isNotEmpty ? priorDeps.last : null,
    );
    await _syncProcessor.enqueue(syncItem);
  }

  @override
  Future<void> deleteProduct(String shopId, String productId) async {
    final existing = _localDb.getProduct(shopId, productId);
    final now = DateTime.now();

    // 1. Soft delete in local Hive box with tenant isolation
    if (existing != null) {
      await _localDb.putProduct(
        shopId,
        existing.copyWith(isActive: false, updatedAt: now),
      );
    }

    // 2. Queue sync operation with dependencies on prior operations
    final priorDeps = _findPendingOperationIds(shopId, productId);
    final syncItem = SyncQueueItem(
      localId: const Uuid().v4(),
      shopId: shopId,
      userId: existing?.updatedBy ?? '',
      operationType: SyncOperationType.deleteProduct,
      entityType: 'product',
      entityId: productId,
      payload: {'isActive': false},
      createdAt: now,
      updatedAt: now,
      dependsOnOperationIds: priorDeps,
      dependsOnOperationId: priorDeps.isNotEmpty ? priorDeps.last : null,
    );
    await _syncProcessor.enqueue(syncItem);
  }

  @override
  Future<void> updateStock(
      String shopId, String productId, int quantityChange) async {
    final product = _localDb.getProduct(shopId, productId);
    if (product == null) {
      throw InventoryFailure.productNotFound();
    }

    final newQty = product.quantity + quantityChange;
    if (newQty < 0) {
      throw InventoryFailure.insufficientStock(product.quantity);
    }

    final now = DateTime.now();
    final updatedProduct = product.copyWith(
      quantity: newQty,
      updatedAt: now,
    );
    await _localDb.putProduct(shopId, updatedProduct);

    // Record local stock movement
    final movementId = const Uuid().v4();
    final movement = StockMovement(
      id: movementId,
      productId: productId,
      productName: product.name,
      type: quantityChange > 0 ? 'restock' : 'adjustment',
      quantityChange: quantityChange,
      quantityBefore: product.quantity,
      quantityAfter: newQty,
      reason: 'Manual stock adjustment',
      userId: product.updatedBy,
      userName: 'Local User',
      source: 'manual',
      createdAt: now,
      shopId: shopId,
    );
    await _localDb.putStockMovement(shopId, movement);

    // Queue sync operation
    final priorDeps = _findPendingOperationIds(shopId, productId);
    final syncItem = SyncQueueItem(
      localId: const Uuid().v4(),
      shopId: shopId,
      userId: product.updatedBy,
      operationType: SyncOperationType.stockAdjustment,
      entityType: 'product',
      entityId: productId,
      payload: {
        'quantityChange': quantityChange,
        'newQuantity': newQty,
        'reason': 'Manual stock adjustment',
      },
      createdAt: now,
      updatedAt: now,
      dependsOnOperationIds: priorDeps,
      dependsOnOperationId: priorDeps.isNotEmpty ? priorDeps.last : null,
    );
    await _syncProcessor.enqueue(syncItem);
  }

  @override
  Future<void> restockWithRecord({
    required String shopId,
    required String productId,
    required String productName,
    required int quantity,
    required String userId,
  }) async {
    final product = _localDb.getProduct(shopId, productId);
    final currentQty = product?.quantity ?? 0;
    final newQty = currentQty + quantity;
    final now = DateTime.now();

    if (product != null) {
      await _localDb.putProduct(
        shopId,
        product.copyWith(quantity: newQty, updatedAt: now),
      );
    }

    // Record local stock movement
    final movementId = const Uuid().v4();
    final movement = StockMovement(
      id: movementId,
      productId: productId,
      productName: productName,
      type: 'restock',
      quantityChange: quantity,
      quantityBefore: currentQty,
      quantityAfter: newQty,
      reason: 'Restock with record',
      userId: userId,
      userName: 'User',
      source: 'restock',
      createdAt: now,
      shopId: shopId,
    );
    await _localDb.putStockMovement(shopId, movement);

    // Queue sync operation
    final priorDeps = _findPendingOperationIds(shopId, productId);
    final syncItem = SyncQueueItem(
      localId: const Uuid().v4(),
      shopId: shopId,
      userId: userId,
      operationType: SyncOperationType.restock,
      entityType: 'product',
      entityId: productId,
      payload: {
        'quantity': quantity,
        'supplier': null,
        'note': null,
      },
      createdAt: now,
      updatedAt: now,
      dependsOnOperationIds: priorDeps,
      dependsOnOperationId: priorDeps.isNotEmpty ? priorDeps.last : null,
    );
    await _syncProcessor.enqueue(syncItem);
  }

  @override
  Future<List<Product>> searchProducts(String shopId, String query) async {
    final lowerQuery = query.toLowerCase();
    return _localDb.productsBox.values
        .where((p) =>
            (p.shopId == shopId || p.shopId.isEmpty) &&
            p.isActive &&
            (p.name.toLowerCase().contains(lowerQuery) ||
                p.sku.toLowerCase().contains(lowerQuery) ||
                (p.barcode?.toLowerCase().contains(lowerQuery) ?? false)))
        .toList();
  }

  @override
  Future<String> generateBarcode(String shopId) async {
    if (_connectivity.isOnline) {
      try {
        final counterRef =
            _firestoreInstance.doc('shops/$shopId/settings/barcode_counter');
        final newCount = await _firestoreInstance.runTransaction<int>((txn) async {
          final snap = await txn.get(counterRef);
          final current = (snap.data()?['value'] as int?) ?? 0;
          final next = current + 1;
          txn.set(counterRef, {'value': next}, SetOptions(merge: true));
          return next;
        }).timeout(const Duration(seconds: 3));

        final shopPrefix = _numericShopPrefix(shopId);
        final counterPart = newCount.toString().padLeft(6, '0');
        return '$shopPrefix$counterPart';
      } catch (_) {
        // Fallback to local deterministic generator
      }
    }

    // Generate deterministic 12-digit barcode locally:
    // 6-digit numeric shop prefix + 6-digit timestamp sequence
    final shopPrefix = _numericShopPrefix(shopId);
    final now = DateTime.now();
    final seq = (now.millisecondsSinceEpoch ~/ 1000) % 1000000;
    return '$shopPrefix${seq.toString().padLeft(6, '0')}';
  }

  String _numericShopPrefix(String shopId) {
    int hash = 0;
    for (final code in shopId.codeUnits) {
      hash = (hash * 31 + code) & 0x7FFFFFFF;
    }
    return (hash % 900000 + 100000).toString();
  }

  // ── Categories ──

  @override
  Stream<List<Category>> watchCategories(String shopId) {
    _attachRemoteListeners(shopId);

    return Stream<List<Category>>.multi((controller) {
      void emitLocal() {
        if (!_localDb.isInitialized) {
          controller.add([]);
          return;
        }
        final list = _localDb.getCategories(shopId);
        list.sort((a, b) => a.name.compareTo(b.name));
        controller.add(list);
      }

      emitLocal();
      final sub = _localDb.categoriesBox.watch().listen((_) => emitLocal());
      controller.onCancel = () => sub.cancel();
    });
  }

  @override
  Future<Category> addCategory(String shopId, Category category) async {
    final now = DateTime.now();
    final id = category.id.isEmpty ? const Uuid().v4() : category.id;
    final newCategory =
        category.copyWith(id: id, shopId: shopId, updatedAt: now);

    await _localDb.putCategory(shopId, newCategory);

    final syncItem = SyncQueueItem(
      localId: const Uuid().v4(),
      shopId: shopId,
      userId: '',
      operationType: SyncOperationType.createCategory,
      entityType: 'category',
      entityId: id,
      payload: {
        'name': newCategory.name,
        'description': newCategory.description,
        'productCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      createdAt: now,
      updatedAt: now,
    );
    await _syncProcessor.enqueue(syncItem);

    return newCategory;
  }

  @override
  Future<void> updateCategory(String shopId, Category category) async {
    final now = DateTime.now();
    final updated = category.copyWith(shopId: shopId, updatedAt: now);

    await _localDb.putCategory(shopId, updated);

    final priorDeps = _findPendingOperationIds(shopId, category.id);
    final syncItem = SyncQueueItem(
      localId: const Uuid().v4(),
      shopId: shopId,
      userId: '',
      operationType: SyncOperationType.updateCategory,
      entityType: 'category',
      entityId: category.id,
      payload: {
        'name': category.name,
        'description': category.description,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      createdAt: now,
      updatedAt: now,
      dependsOnOperationIds: priorDeps,
      dependsOnOperationId: priorDeps.isNotEmpty ? priorDeps.last : null,
    );
    await _syncProcessor.enqueue(syncItem);
  }

  @override
  Future<void> deleteCategory(String shopId, String categoryId) async {
    await _localDb.deleteCategory(shopId, categoryId);

    final now = DateTime.now();
    final priorDeps = _findPendingOperationIds(shopId, categoryId);
    final syncItem = SyncQueueItem(
      localId: const Uuid().v4(),
      shopId: shopId,
      userId: '',
      operationType: SyncOperationType.deleteCategory,
      entityType: 'category',
      entityId: categoryId,
      payload: {},
      createdAt: now,
      updatedAt: now,
      dependsOnOperationIds: priorDeps,
      dependsOnOperationId: priorDeps.isNotEmpty ? priorDeps.last : null,
    );
    await _syncProcessor.enqueue(syncItem);
  }
}
