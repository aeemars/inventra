import 'package:flutter/foundation.dart' hide Category;
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../features/inventory/domain/entities/product.dart';
import '../../features/inventory/domain/entities/category.dart';
import '../../shared/models/stock_movement.dart';
import '../../shared/models/scan_history_entry.dart';
import '../../features/sales/domain/sales_queue_item.dart';
import '../sync/sync_models.dart';

/// Centralized manager for all local persistent Hive boxes.
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

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      productsBox = await Hive.openBox<Product>('products');
      categoriesBox = await Hive.openBox<Category>('categories');
      salesTransactionsBox =
          await Hive.openBox<SaleTransaction>('sales_transactions');
      stockMovementsBox =
          await Hive.openBox<StockMovement>('stock_movements');
      scanHistoryBox =
          await Hive.openBox<ScanHistoryEntry>('scan_history');
      salesQueueBox = await Hive.openBox<SalesQueueItem>('sales_queue');
      syncQueueBox = await Hive.openBox<SyncQueueItem>('sync_queue');
      syncMetadataBox = await Hive.openBox<dynamic>('sync_metadata');
      appPrefsBox = await Hive.openBox<dynamic>('app_prefs');

      _initialized = true;
      debugPrint('📦 LocalDatabase initialized with all boxes opened.');
    } catch (e) {
      debugPrint('⚠️ LocalDatabase initialization error: $e');
      rethrow;
    }
  }

  /// Clears local shop data (e.g. on account logout or shop switch)
  /// to ensure strict tenant isolation.
  Future<void> clearShopData() async {
    if (!_initialized) return;
    await productsBox.clear();
    await categoriesBox.clear();
    await salesTransactionsBox.clear();
    await stockMovementsBox.clear();
    await scanHistoryBox.clear();
    await salesQueueBox.clear();
    await syncQueueBox.clear();
    await syncMetadataBox.clear();
  }
}
