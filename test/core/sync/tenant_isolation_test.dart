import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:inventra/core/cache/hive_adapters.dart';
import 'package:inventra/core/cache/local_database.dart';
import 'package:inventra/core/sync/sync_models.dart';
import 'package:inventra/features/inventory/data/repositories/offline_product_repository.dart';
import 'package:inventra/features/inventory/domain/entities/category.dart';
import 'package:inventra/features/inventory/domain/entities/product.dart';
import 'package:inventra/shared/models/stock_movement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalDatabase localDb;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_tenant_isolation_test_');
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
    localDb = LocalDatabase.instance;
    await localDb.initialize();
    await localDb.clearShopData(force: true);
  });

  group('Multi-shop / Local Tenant Isolation', () {
    const shopA = 'shop_alpha';
    const shopB = 'shop_beta';

    test('Products in Shop A and Shop B with same ID do not collide or overwrite', () async {
      final repo = OfflineProductRepository(localDb: localDb);

      final productA = Product(
        id: 'common_sku_01',
        shopId: shopA,
        name: 'Coffee Arabica (Shop A)',
        sku: 'CA-01',
        sellingPrice: 15.0,
        costPrice: 8.0,
        quantity: 50,
        reorderLevel: 10,
        createdBy: 'user_1',
        updatedBy: 'user_1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final productB = Product(
        id: 'common_sku_01',
        shopId: shopB,
        name: 'Tea Earl Grey (Shop B)',
        sku: 'TEG-01',
        sellingPrice: 10.0,
        costPrice: 4.0,
        quantity: 120,
        reorderLevel: 15,
        createdBy: 'user_2',
        updatedBy: 'user_2',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Persist both products under their respective shops
      await localDb.putProduct(shopA, productA);
      await localDb.putProduct(shopB, productB);

      // Verify direct scoped retrieval
      final retrievedA = localDb.getProduct(shopA, 'common_sku_01');
      final retrievedB = localDb.getProduct(shopB, 'common_sku_01');

      expect(retrievedA, isNotNull);
      expect(retrievedA!.name, 'Coffee Arabica (Shop A)');
      expect(retrievedA.quantity, 50);

      expect(retrievedB, isNotNull);
      expect(retrievedB!.name, 'Tea Earl Grey (Shop B)');
      expect(retrievedB.quantity, 120);

      // Verify repository scoped retrieval
      final repoProdA = await repo.getProduct(shopA, 'common_sku_01');
      final repoProdB = await repo.getProduct(shopB, 'common_sku_01');

      expect(repoProdA?.name, 'Coffee Arabica (Shop A)');
      expect(repoProdB?.name, 'Tea Earl Grey (Shop B)');

      // Verify repository lists
      final productsA = await repo.watchProducts(shopA).first;
      final productsB = await repo.watchProducts(shopB).first;

      expect(productsA.length, 1);
      expect(productsA.first.name, 'Coffee Arabica (Shop A)');

      expect(productsB.length, 1);
      expect(productsB.first.name, 'Tea Earl Grey (Shop B)');
    });

    test('Barcode queries are strictly tenant-isolated', () async {
      final repo = OfflineProductRepository(localDb: localDb);

      final productA = Product(
        id: 'prod_barcode_a',
        shopId: shopA,
        barcode: '8901234567890',
        name: 'Milk (Shop A)',
        sku: 'MILK-A',
        sellingPrice: 4.5,
        costPrice: 2.5,
        quantity: 30,
        reorderLevel: 5,
        createdBy: 'user_1',
        updatedBy: 'user_1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final productB = Product(
        id: 'prod_barcode_b',
        shopId: shopB,
        barcode: '8901234567890', // Same barcode in different store!
        name: 'Milk (Shop B)',
        sku: 'MILK-B',
        sellingPrice: 4.0,
        costPrice: 2.0,
        quantity: 60,
        reorderLevel: 10,
        createdBy: 'user_2',
        updatedBy: 'user_2',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await localDb.putProduct(shopA, productA);
      await localDb.putProduct(shopB, productB);

      final matchA = await repo.findByBarcode(shopA, '8901234567890');
      final matchB = await repo.findByBarcode(shopB, '8901234567890');

      expect(matchA, isNotNull);
      expect(matchA!.name, 'Milk (Shop A)');

      expect(matchB, isNotNull);
      expect(matchB!.name, 'Milk (Shop B)');

      // Non-existent in Shop C
      final matchC = await repo.findByBarcode('shop_gamma', '8901234567890');
      expect(matchC, isNull);
    });

    test('Categories are isolated between shops', () async {
      final catA = Category(
        id: 'cat_beverages',
        shopId: shopA,
        name: 'Beverages Alpha',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final catB = Category(
        id: 'cat_beverages',
        shopId: shopB,
        name: 'Beverages Beta',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await localDb.putCategory(shopA, catA);
      await localDb.putCategory(shopB, catB);

      final fetchedA = localDb.getCategory(shopA, 'cat_beverages');
      final fetchedB = localDb.getCategory(shopB, 'cat_beverages');

      expect(fetchedA?.name, 'Beverages Alpha');
      expect(fetchedB?.name, 'Beverages Beta');

      final listA = localDb.getCategories(shopA);
      final listB = localDb.getCategories(shopB);

      expect(listA.length, 1);
      expect(listA.first.name, 'Beverages Alpha');

      expect(listB.length, 1);
      expect(listB.first.name, 'Beverages Beta');
    });

    test('Transactions and Stock Movements are scoped strictly by shopId', () async {
      final now = DateTime.now();

      final txA = SaleTransaction(
        id: 'tx_101',
        shopId: shopA,
        type: 'sale',
        items: [],
        subtotal: 100,
        discount: 0,
        taxAmount: 0,
        total: 100,
        paymentMethod: 'cash',
        status: TransactionStatus.completedLocal,
        createdBy: 'user_1',
        createdByName: 'Alice',
        createdAt: now,
      );

      final txB = SaleTransaction(
        id: 'tx_102',
        shopId: shopB,
        type: 'sale',
        items: [],
        subtotal: 200,
        discount: 0,
        taxAmount: 0,
        total: 200,
        paymentMethod: 'card',
        status: TransactionStatus.completedLocal,
        createdBy: 'user_2',
        createdByName: 'Bob',
        createdAt: now,
      );

      await localDb.putTransaction(shopA, txA);
      await localDb.putTransaction(shopB, txB);

      final listA = localDb.getTransactions(shopA);
      final listB = localDb.getTransactions(shopB);

      expect(listA.length, 1);
      expect(listA.first.id, 'tx_101');
      expect(listA.first.shopId, shopA);

      expect(listB.length, 1);
      expect(listB.first.id, 'tx_102');
      expect(listB.first.shopId, shopB);

      // Stock movements
      final movementA = StockMovement(
        id: 'mov_1',
        shopId: shopA,
        productId: 'prod_1',
        productName: 'P1',
        type: 'sale',
        quantityChange: -2,
        quantityBefore: 10,
        quantityAfter: 8,
        reference: 'tx_101',
        userId: 'user_1',
        userName: 'Alice',
        source: 'pos',
        createdAt: now,
      );

      final movementB = StockMovement(
        id: 'mov_2',
        shopId: shopB,
        productId: 'prod_2',
        productName: 'P2',
        type: 'sale',
        quantityChange: -5,
        quantityBefore: 20,
        quantityAfter: 15,
        reference: 'tx_102',
        userId: 'user_2',
        userName: 'Bob',
        source: 'pos',
        createdAt: now,
      );

      await localDb.putStockMovement(shopA, movementA);
      await localDb.putStockMovement(shopB, movementB);

      final movementsA = localDb.getStockMovements(shopA);
      final movementsB = localDb.getStockMovements(shopB);

      expect(movementsA.length, 1);
      expect(movementsA.first.id, 'mov_1');

      expect(movementsB.length, 1);
      expect(movementsB.first.id, 'mov_2');
    });

    test('Non-destructive logout preserves unsynchronized operations in queue and data', () async {
      final now = DateTime.now();

      final queueItem = SyncQueueItem(
        localId: 'op_pending_1',
        shopId: shopA,
        userId: 'user_1',
        operationType: SyncOperationType.createSale,
        entityType: 'sale',
        entityId: 'tx_pending_1',
        payload: {'items': []},
        createdAt: now,
        updatedAt: now,
      );

      await localDb.syncQueueBox.put(queueItem.localId, queueItem);

      final tx = SaleTransaction(
        id: 'tx_pending_1',
        shopId: shopA,
        type: 'sale',
        items: [],
        subtotal: 50,
        discount: 0,
        taxAmount: 0,
        total: 50,
        paymentMethod: 'cash',
        status: TransactionStatus.completedLocal,
        createdBy: 'user_1',
        createdByName: 'Alice',
        createdAt: now,
      );
      await localDb.putTransaction(shopA, tx);

      // Attempt safe clear without force
      await localDb.clearShopData(shopId: shopA, force: false);

      // Must NOT be cleared because there is pending sync!
      expect(localDb.syncQueueBox.containsKey('op_pending_1'), isTrue);
      expect(localDb.getTransaction(shopA, 'tx_pending_1'), isNotNull);

      // Clearing Shop B (which has no pending sync) should be allowed without clearing Shop A
      await localDb.clearShopData(shopId: shopB, force: false);
      expect(localDb.syncQueueBox.containsKey('op_pending_1'), isTrue);
    });
  });
}
