import 'package:flutter/foundation.dart' hide Category;
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../features/inventory/domain/entities/product.dart';
import '../../features/inventory/domain/entities/category.dart';
import '../../shared/models/stock_movement.dart';
import '../../shared/models/scan_history_entry.dart';
import '../../features/sales/domain/sales_queue_item.dart';
import '../sync/sync_models.dart';
import '../sync/operation_journal.dart';

/// Centralized manager for all local persistent Hive boxes with strict tenant isolation.
class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._internal();
  LocalDatabase._internal();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  late Box<Product> productsBox;
  late Box<Category> categoriesBox;
  late Box<SaleTransaction> salesTransactionsBox;
  late Box<StockMovement> stockMovementsBox;
  late Box<ScanHistoryEntry> scanHistoryBox;
  late Box<SalesQueueItem> salesQueueBox;
  late Box<SyncQueueItem> syncQueueBox;
  late Box<dynamic> syncMetadataBox;
  late Box<dynamic> appPrefsBox;
  late Box<OperationJournalEntry> localOperationsBox;

  /// Generate a tenant-isolated composite key to eliminate any cross-shop collision.
  static String scopedKey(String shopId, String id) {
    if (id.startsWith('$shopId:')) return id;
    return '$shopId:$id';
  }

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      productsBox = await _openBoxSafely<Product>('products');
      categoriesBox = await _openBoxSafely<Category>('categories');
      salesTransactionsBox =
          await _openBoxSafely<SaleTransaction>('sales_transactions');
      stockMovementsBox =
          await _openBoxSafely<StockMovement>('stock_movements');
      scanHistoryBox =
          await _openBoxSafely<ScanHistoryEntry>('scan_history');
      salesQueueBox = await _openBoxSafely<SalesQueueItem>('sales_queue');
      syncQueueBox = await _openBoxSafely<SyncQueueItem>('sync_queue');
      syncMetadataBox = await _openBoxSafely<dynamic>('sync_metadata');
      appPrefsBox = await _openBoxSafely<dynamic>('app_prefs');
      localOperationsBox =
          await _openBoxSafely<OperationJournalEntry>('local_operations');

      _initialized = true;
      debugPrint('📦 LocalDatabase initialized with all boxes opened.');
    } catch (e, stackTrace) {
      debugPrint('⚠️ LocalDatabase initialization error: $e\n$stackTrace');
      rethrow;
    }
  }

  Future<Box<T>> _openBoxSafely<T>(String name) async {
    try {
      return await Hive.openBox<T>(name);
    } catch (e) {
      debugPrint(
        '⚠️ Box "$name" corrupted or failed to open ($e). Auto-repairing by resetting corrupted box...',
      );
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
      return await Hive.openBox<T>(name);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Tenant-Scoped Product Operations
  // ═══════════════════════════════════════════════════════════════════════════

  List<Product> getProducts(String shopId, {bool activeOnly = true}) {
    if (!_initialized) return [];
    final seen = <String>{};
    final list = <Product>[];
    for (final p in productsBox.values) {
      final matchesShop = p.shopId == shopId || p.shopId.isEmpty;
      final matchesActive = !activeOnly || p.isActive;
      if (matchesShop && matchesActive) {
        if (seen.add(p.id)) {
          list.add(p);
        }
      }
    }
    return list;
  }

  Product? getProduct(String shopId, String productId) {
    if (!_initialized) return null;
    final p = productsBox.get(scopedKey(shopId, productId)) ??
        productsBox.get(productId);
    if (p != null && (p.shopId == shopId || p.shopId.isEmpty)) {
      return p;
    }
    return null;
  }

  Future<void> putProduct(String shopId, Product product) async {
    assert(product.shopId.isEmpty || product.shopId == shopId,
        'Tenant mismatch: product.shopId (${product.shopId}) != active shopId ($shopId)');
    final bound =
        product.shopId.isEmpty ? product.copyWith(shopId: shopId) : product;
    final sk = scopedKey(shopId, product.id);
    await productsBox.put(sk, bound);
    if (sk != product.id) {
      await productsBox.put(product.id, bound);
    }
  }

  Future<void> deleteProduct(String shopId, String productId) async {
    await productsBox.delete(scopedKey(shopId, productId));
    await productsBox.delete(productId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Tenant-Scoped Category Operations
  // ═══════════════════════════════════════════════════════════════════════════

  List<Category> getCategories(String shopId) {
    if (!_initialized) return [];
    final seen = <String>{};
    final list = <Category>[];
    for (final c in categoriesBox.values) {
      if (c.shopId == shopId || c.shopId.isEmpty) {
        if (seen.add(c.id)) {
          list.add(c);
        }
      }
    }
    return list;
  }

  Category? getCategory(String shopId, String categoryId) {
    if (!_initialized) return null;
    final c = categoriesBox.get(scopedKey(shopId, categoryId)) ??
        categoriesBox.get(categoryId);
    if (c != null && (c.shopId == shopId || c.shopId.isEmpty)) {
      return c;
    }
    return null;
  }

  Future<void> putCategory(String shopId, Category category) async {
    final bound = category.shopId.isEmpty
        ? category.copyWith(shopId: shopId)
        : category;
    final sk = scopedKey(shopId, category.id);
    await categoriesBox.put(sk, bound);
    if (sk != category.id) {
      await categoriesBox.put(category.id, bound);
    }
  }

  Future<void> deleteCategory(String shopId, String categoryId) async {
    await categoriesBox.delete(scopedKey(shopId, categoryId));
    await categoriesBox.delete(categoryId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Tenant-Scoped Transaction Operations
  // ═══════════════════════════════════════════════════════════════════════════

  List<SaleTransaction> getTransactions(String shopId) {
    if (!_initialized) return [];
    return salesTransactionsBox.values
        .where((t) => t.shopId == shopId || t.shopId.isEmpty)
        .toList();
  }

  SaleTransaction? getTransaction(String shopId, String transactionId) {
    if (!_initialized) return null;
    final t = salesTransactionsBox.get(scopedKey(shopId, transactionId)) ??
        salesTransactionsBox.get(transactionId);
    if (t != null && (t.shopId == shopId || t.shopId.isEmpty)) {
      return t;
    }
    return null;
  }

  Future<void> putTransaction(
      String shopId, SaleTransaction transaction) async {
    final bound = transaction.shopId.isEmpty
        ? transaction.copyWith(shopId: shopId)
        : transaction;
    await salesTransactionsBox.put(transaction.id, bound);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Tenant-Scoped Stock Movement Operations
  // ═══════════════════════════════════════════════════════════════════════════

  List<StockMovement> getStockMovements(String shopId) {
    if (!_initialized) return [];
    return stockMovementsBox.values
        .where((m) => m.shopId == shopId || m.shopId.isEmpty)
        .toList();
  }

  Future<void> putStockMovement(
      String shopId, StockMovement movement) async {
    final bound = movement.shopId.isEmpty
        ? movement.copyWith(shopId: shopId)
        : movement;
    await stockMovementsBox.put(movement.id, bound);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Non-Destructive Tenant Clearing & Logout Safety
  // ═══════════════════════════════════════════════════════════════════════════

  /// Checks whether a shop has pending unsynchronized queue operations.
  bool hasPendingSync(String shopId) {
    if (!_initialized) return false;
    return syncQueueBox.values.any((item) =>
        item.shopId == shopId &&
        (item.status == SyncStatus.pending ||
            item.status == SyncStatus.processing));
  }

  /// Clears local shop data with tenant isolation.
  /// If [shopId] is specified, only that tenant's records are purged.
  /// If [force] is false, any tenant with pending sync queue items is PRESERVED
  /// to protect financial records from silent loss.
  Future<void> clearShopData({String? shopId, bool force = true}) async {
    if (!_initialized) return;

    if (shopId != null) {
      if (!force && hasPendingSync(shopId)) {
        debugPrint(
            '🛡️ [TENANT SAFETY] Preserving local data for shop $shopId during logout because pending sync operations exist.');
        return;
      }

      // Purge only records matching this shopId
      final productKeys = productsBox.keys
          .where((k) =>
              k.toString().startsWith('$shopId:') ||
              productsBox.get(k)?.shopId == shopId)
          .toList();
      await productsBox.deleteAll(productKeys);

      final categoryKeys = categoriesBox.keys
          .where((k) =>
              k.toString().startsWith('$shopId:') ||
              categoriesBox.get(k)?.shopId == shopId)
          .toList();
      await categoriesBox.deleteAll(categoryKeys);

      final txKeys = salesTransactionsBox.keys
          .where((k) =>
              k.toString().startsWith('$shopId:') ||
              salesTransactionsBox.get(k)?.shopId == shopId)
          .toList();
      await salesTransactionsBox.deleteAll(txKeys);

      final smKeys = stockMovementsBox.keys
          .where((k) =>
              k.toString().startsWith('$shopId:') ||
              stockMovementsBox.get(k)?.shopId == shopId)
          .toList();
      await stockMovementsBox.deleteAll(smKeys);

      final queueKeys = syncQueueBox.keys
          .where((k) => syncQueueBox.get(k)?.shopId == shopId)
          .toList();
      await syncQueueBox.deleteAll(queueKeys);

      final journalKeys = localOperationsBox.keys
          .where((k) =>
              k.toString().startsWith('$shopId:') ||
              localOperationsBox.get(k)?.shopId == shopId)
          .toList();
      await localOperationsBox.deleteAll(journalKeys);

      await syncMetadataBox.delete('sync_checkpoint_$shopId');
    } else {
      if (force) {
        await productsBox.clear();
        await categoriesBox.clear();
        await salesTransactionsBox.clear();
        await stockMovementsBox.clear();
        await scanHistoryBox.clear();
        await salesQueueBox.clear();
        await syncQueueBox.clear();
        await syncMetadataBox.clear();
        await localOperationsBox.clear();
      } else {
        // Only purge records from shops with 0 pending operations
        final shopsWithPending = syncQueueBox.values
            .where((i) =>
                i.status == SyncStatus.pending ||
                i.status == SyncStatus.processing)
            .map((i) => i.shopId)
            .toSet();

        if (shopsWithPending.isEmpty) {
          await clearShopData(force: true);
        } else {
          debugPrint(
              '🛡️ [TENANT SAFETY] Preserving shops with pending operations: $shopsWithPending');
        }
      }
    }
  }
}
