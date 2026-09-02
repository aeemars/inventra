import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:inventra/core/cache/hive_adapters.dart';
import 'package:inventra/core/cache/local_database.dart';
import 'package:inventra/features/inventory/domain/entities/product.dart';
import 'package:inventra/features/sales/presentation/controllers/sales_queue_provider.dart';
import 'package:inventra/features/scanner/data/scanner_repository.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_sales_test_');
    Hive.init(tempDir.path);
    registerHiveAdapters();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await LocalDatabase.instance.initialize();
    await LocalDatabase.instance.clearShopData();
  });

  group('Offline Sales and Cart Persistence', () {
    final now = DateTime.now();

    final productA = Product(
      id: 'prod-A',
      name: 'Product A',
      sku: 'SKU-A',
      costPrice: 50.0,
      sellingPrice: 100.0,
      quantity: 10,
      reorderLevel: 2,
      unit: 'pcs',
      createdAt: now,
      updatedAt: now,
      createdBy: 'user-1',
      updatedBy: 'user-1',
    );

    final productB = Product(
      id: 'prod-B',
      name: 'Product B',
      sku: 'SKU-B',
      costPrice: 150.0,
      sellingPrice: 250.0,
      quantity: 5,
      reorderLevel: 1,
      unit: 'pcs',
      createdAt: now,
      updatedAt: now,
      createdBy: 'user-1',
      updatedBy: 'user-1',
    );

    test('persists cart items in Hive across notifier restart', () async {
      final notifier1 = SalesQueueNotifier(LocalDatabase.instance);

      notifier1.addOrIncrement(productA, quantity: 2);
      notifier1.addOrIncrement(productB, quantity: 1);

      expect(notifier1.itemCount, 2);
      expect(notifier1.subtotal, 450.0); // 2*100 + 1*250

      // Simulate app restart by creating a new notifier instance
      final notifier2 = SalesQueueNotifier(LocalDatabase.instance);

      expect(notifier2.itemCount, 2);
      expect(notifier2.subtotal, 450.0);
      expect(notifier2.state.any((i) => i.product.id == 'prod-A'), true);
      expect(notifier2.state.any((i) => i.product.id == 'prod-B'), true);

      // Clearing wipes persistent cart
      await notifier2.clear();
      expect(notifier2.itemCount, 0);

      final notifier3 = SalesQueueNotifier(LocalDatabase.instance);
      expect(notifier3.itemCount, 0);
    });

    test('performs offline multi-item sale and deducts local stock', () async {
      await LocalDatabase.instance.productsBox.put(productA.id, productA);
      await LocalDatabase.instance.productsBox.put(productB.id, productB);

      final scannerRepo = ScannerRepository(localDb: LocalDatabase.instance);

      final txId = await scannerRepo.performMultiItemSale(
        shopId: 'shop-test',
        items: [
          {'productId': productA.id, 'quantity': 3, 'unitPrice': 100.0},
          {'productId': productB.id, 'quantity': 2, 'unitPrice': 250.0},
        ],
        userId: 'user-1',
        userName: 'Test User',
      );

      expect(txId, isNotEmpty);

      // 1. Check stock was deducted immediately in Hive
      final updatedA = LocalDatabase.instance.productsBox.get(productA.id);
      final updatedB = LocalDatabase.instance.productsBox.get(productB.id);

      expect(updatedA!.quantity, 7); // 10 - 3
      expect(updatedB!.quantity, 3); // 5 - 2

      // 2. Check local transaction was recorded in Hive
      final tx = LocalDatabase.instance.salesTransactionsBox.get(txId);
      expect(tx, isNotNull);
      expect(tx!.total, 800.0); // 3*100 + 2*250
      expect(tx.status, 'completed');
      expect(tx.items.length, 2);

      // 3. Check local stock movements were recorded
      final movements = LocalDatabase.instance.stockMovementsBox.values.toList();
      expect(movements.length, 2);
      expect(movements.every((m) => m.type == 'sale'), true);

      // 4. Check sync queue has the queued operation
      final queueItems = LocalDatabase.instance.syncQueueBox.values.toList();
      expect(queueItems.length, 1);
      expect(queueItems.first.localId, txId);
      expect(queueItems.first.entityType, 'sale');
    });

    test('prevents offline sale when stock is insufficient', () async {
      await LocalDatabase.instance.productsBox.put(productA.id, productA);

      final scannerRepo = ScannerRepository(localDb: LocalDatabase.instance);

      expect(
        () async => await scannerRepo.performMultiItemSale(
          shopId: 'shop-test',
          items: [
            {'productId': productA.id, 'quantity': 15}, // Only 10 available
          ],
          userId: 'user-1',
          userName: 'Test User',
        ),
        throwsA(isA<InsufficientStockException>()),
      );

      // Stock remains untouched
      final unchanged = LocalDatabase.instance.productsBox.get(productA.id);
      expect(unchanged!.quantity, 10);
    });
  });
}
