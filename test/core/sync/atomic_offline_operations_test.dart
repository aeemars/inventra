import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:inventra/core/cache/hive_adapters.dart';
import 'package:inventra/core/cache/local_database.dart';
import 'package:inventra/core/sync/operation_journal.dart';
import 'package:inventra/core/sync/sync_models.dart';
import 'package:inventra/features/inventory/domain/entities/product.dart';
import 'package:inventra/shared/models/stock_movement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalDatabase localDb;

  const testShopId = 'shop_atomic_test';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_atomic_test_');
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

  group('Atomic Offline Operations & Crash Recovery', () {
    test('Standard atomic sale commits product deductions, transaction, movements, and queue entry', () async {
      final now = DateTime.now();

      // Setup 2 products
      final p1 = Product(
        id: 'p1',
        shopId: testShopId,
        name: 'Product 1',
        sku: 'SKU-1',
        sellingPrice: 20.0,
        costPrice: 10.0,
        quantity: 50,
        reorderLevel: 5,
        createdBy: 'user_1',
        updatedBy: 'user_1',
        createdAt: now,
        updatedAt: now,
      );

      final p2 = Product(
        id: 'p2',
        shopId: testShopId,
        name: 'Product 2',
        sku: 'SKU-2',
        sellingPrice: 35.0,
        costPrice: 20.0,
        quantity: 30,
        reorderLevel: 5,
        createdBy: 'user_1',
        updatedBy: 'user_1',
        createdAt: now,
        updatedAt: now,
      );

      await localDb.putProduct(testShopId, p1);
      await localDb.putProduct(testShopId, p2);

      final saleItems = [
        {'productId': 'p1', 'quantity': 3, 'unitPrice': 20.0},
        {'productId': 'p2', 'quantity': 2, 'unitPrice': 35.0},
      ];

      final txId = await OfflineOperationManager.executeAtomicSale(
        shopId: testShopId,
        operationId: 'op_sale_101',
        userId: 'cashier_1',
        userName: 'Alice',
        items: saleItems,
        paymentMethod: 'cash',
        discount: 5.0,
        localDb: localDb,
      );

      expect(txId, 'op_sale_101');

      // 1. Check stock deductions
      final updatedP1 = localDb.getProduct(testShopId, 'p1');
      final updatedP2 = localDb.getProduct(testShopId, 'p2');
      expect(updatedP1?.quantity, 47); // 50 - 3
      expect(updatedP2?.quantity, 28); // 30 - 2

      // 2. Check local transaction record
      final tx = localDb.getTransaction(testShopId, txId);
      expect(tx, isNotNull);
      expect(tx!.status, TransactionStatus.completedLocal);
      expect(tx.subtotal, 130.0); // (3*20) + (2*35) = 60 + 70 = 130
      expect(tx.discount, 5.0);
      expect(tx.total, 125.0);

      // 3. Check stock movements
      final movements = localDb.getStockMovements(testShopId);
      expect(movements.length, 2);
      expect(movements.any((m) => m.productId == 'p1' && m.quantityChange == -3), isTrue);
      expect(movements.any((m) => m.productId == 'p2' && m.quantityChange == -2), isTrue);

      // 4. Check sync queue entry
      final queueItem = localDb.syncQueueBox.get(txId);
      expect(queueItem, isNotNull);
      expect(queueItem!.shopId, testShopId);
      expect(queueItem.operationType, SyncOperationType.createSale);
      expect(queueItem.status, SyncStatus.pending);

      // 5. Check journal status
      final journalEntry = localDb.localOperationsBox.get(LocalDatabase.scopedKey(testShopId, txId));
      expect(journalEntry, isNotNull);
      expect(journalEntry!.status, LocalOperationStatus.committed);
    });

    test('Crash during PREPARING stage rolls back partial mutations to original stock', () async {
      final now = DateTime.now();

      final p1 = Product(
        id: 'p_rolled_back',
        shopId: testShopId,
        name: 'Product To Roll Back',
        sku: 'SKU-RB',
        sellingPrice: 50.0,
        costPrice: 25.0,
        quantity: 100,
        reorderLevel: 10,
        createdBy: 'user_1',
        updatedBy: 'user_1',
        createdAt: now,
        updatedAt: now,
      );
      await localDb.putProduct(testShopId, p1);

      // Simulate partial mutation where stock was accidentally modified to 90 before crash
      await localDb.putProduct(testShopId, p1.copyWith(quantity: 90));

      // Inject an uncommitted journal entry in 'preparing' state with backupState = 100
      final journalEntry = OperationJournalEntry(
        operationId: 'op_crashed_prep',
        shopId: testShopId,
        operationType: 'sale',
        status: LocalOperationStatus.preparing,
        targetMutations: {
          'items': [
            {'productId': 'p_rolled_back', 'quantity': 10}
          ]
        },
        backupState: {
          'products': {
            'p_rolled_back': {'quantity': 100}
          }
        },
        createdAt: now,
      );
      await localDb.localOperationsBox.put(
        LocalDatabase.scopedKey(testShopId, 'op_crashed_prep'),
        journalEntry,
      );

      // Run startup recovery
      await OfflineOperationManager.recoverIncompleteOperations(localDb: localDb);

      // Stock should have been restored back to 100
      final recoveredProd = localDb.getProduct(testShopId, 'p_rolled_back');
      expect(recoveredProd?.quantity, 100);

      // Journal status should now be rolledBack
      final updatedJournal = localDb.localOperationsBox.get(
        LocalDatabase.scopedKey(testShopId, 'op_crashed_prep'),
      );
      expect(updatedJournal?.status, LocalOperationStatus.rolledBack);

      // No orphaned transaction or queue item
      expect(localDb.getTransaction(testShopId, 'op_crashed_prep'), isNull);
      expect(localDb.syncQueueBox.containsKey('op_crashed_prep'), isFalse);
    });

    test('Crash during COMMITTING stage replays and completes sync queue write', () async {
      final now = DateTime.now();

      final p1 = Product(
        id: 'p_replay',
        shopId: testShopId,
        name: 'Product To Replay',
        sku: 'SKU-RP',
        sellingPrice: 10.0,
        costPrice: 5.0,
        quantity: 20,
        reorderLevel: 5,
        createdBy: 'user_1',
        updatedBy: 'user_1',
        createdAt: now,
        updatedAt: now,
      );
      await localDb.putProduct(testShopId, p1);

      // Simulate crash after stock deduction (quantity 16) and transaction write,
      // but BEFORE sync queue item was persisted.
      await localDb.putProduct(testShopId, p1.copyWith(quantity: 16));

      final tx = SaleTransaction(
        id: 'op_crashed_commit',
        shopId: testShopId,
        type: 'sale',
        items: const [
          SaleItem(
            productId: 'p_replay',
            productName: 'Product To Replay',
            sku: 'SKU-RP',
            quantity: 4,
            unitPrice: 10.0,
            totalPrice: 40.0,
          )
        ],
        subtotal: 40,
        discount: 0,
        taxAmount: 0,
        total: 40,
        paymentMethod: 'cash',
        status: TransactionStatus.completedLocal,
        createdBy: 'user_1',
        createdByName: 'Alice',
        createdAt: now,
      );
      await localDb.putTransaction(testShopId, tx);

      // Ensure syncQueueBox does NOT contain this item yet
      expect(localDb.syncQueueBox.containsKey('op_crashed_commit'), isFalse);

      // Inject journal in 'committing' state
      final journalEntry = OperationJournalEntry(
        operationId: 'op_crashed_commit',
        shopId: testShopId,
        operationType: 'sale',
        status: LocalOperationStatus.committing,
        targetMutations: {
          'items': [
            {'productId': 'p_replay', 'quantity': 4}
          ],
          'paymentMethod': 'cash',
          'discount': 0.0,
        },
        backupState: {
          'products': {
            'p_replay': {'quantity': 20}
          }
        },
        createdAt: now,
      );
      await localDb.localOperationsBox.put(
        LocalDatabase.scopedKey(testShopId, 'op_crashed_commit'),
        journalEntry,
      );

      // Run startup recovery
      await OfflineOperationManager.recoverIncompleteOperations(localDb: localDb);

      // Sync queue item should now be successfully restored/replayed
      final replayedQueueItem = localDb.syncQueueBox.get('op_crashed_commit');
      expect(replayedQueueItem, isNotNull);
      expect(replayedQueueItem!.shopId, testShopId);
      expect(replayedQueueItem.status, SyncStatus.pending);

      // Journal entry should now be marked committed
      final updatedJournal = localDb.localOperationsBox.get(
        LocalDatabase.scopedKey(testShopId, 'op_crashed_commit'),
      );
      expect(updatedJournal?.status, LocalOperationStatus.committed);

      // Stock remains deducted (16), not double deducted
      final prod = localDb.getProduct(testShopId, 'p_replay');
      expect(prod?.quantity, 16);
    });
  });
}
