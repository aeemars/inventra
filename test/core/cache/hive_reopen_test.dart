import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:inventra/core/cache/hive_adapters.dart';
import 'package:inventra/core/sync/operation_journal.dart';
import 'package:inventra/core/sync/sync_models.dart';
import 'package:inventra/features/inventory/domain/entities/category.dart';
import 'package:inventra/features/inventory/domain/entities/product.dart';
import 'package:inventra/shared/models/scan_history_entry.dart';
import 'package:inventra/shared/models/stock_movement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    registerHiveAdapters();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_reopen_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Test writing and reopening all boxes with sample data', () async {
    final now = DateTime.now();

    // 1. Open boxes and write sample entities
    final productsBox = await Hive.openBox<Product>('products');
    await productsBox.put(
      'p1',
      Product(
        id: 'p1',
        name: 'Test Product',
        sku: 'SKU-001',
        costPrice: 10.0,
        sellingPrice: 15.0,
        quantity: 100,
        reorderLevel: 10,
        createdAt: now,
        updatedAt: now,
        createdBy: 'u1',
        updatedBy: 'u1',
        shopId: 's1',
      ),
    );
    await productsBox.close();

    final categoriesBox = await Hive.openBox<Category>('categories');
    await categoriesBox.put(
      'c1',
      Category(
        id: 'c1',
        name: 'Test Category',
        createdAt: now,
        updatedAt: now,
        shopId: 's1',
      ),
    );
    await categoriesBox.close();

    final salesBox = await Hive.openBox<SaleTransaction>('sales_transactions');
    await salesBox.put(
      'tx1',
      SaleTransaction(
        id: 'tx1',
        type: 'sale',
        items: [
          SaleItem(
            productId: 'p1',
            productName: 'Test Product',
            sku: 'SKU-001',
            quantity: 2,
            unitPrice: 15.0,
            totalPrice: 30.0,
          ),
        ],
        subtotal: 30.0,
        discount: 0.0,
        taxAmount: 0.0,
        total: 30.0,
        paymentMethod: 'cash',
        status: 'completed_local',
        createdBy: 'u1',
        createdByName: 'User 1',
        createdAt: now,
        shopId: 's1',
        serverTransactionId: 'srv_1',
      ),
    );
    await salesBox.close();

    final stockBox = await Hive.openBox<StockMovement>('stock_movements');
    await stockBox.put(
      'sm1',
      StockMovement(
        id: 'sm1',
        productId: 'p1',
        productName: 'Test Product',
        type: 'sale',
        quantityChange: -2,
        quantityBefore: 100,
        quantityAfter: 98,
        userId: 'u1',
        userName: 'User 1',
        source: 'local',
        createdAt: now,
        shopId: 's1',
      ),
    );
    await stockBox.close();

    final scanBox = await Hive.openBox<ScanHistoryEntry>('scan_history');
    await scanBox.put(
      'sc1',
      ScanHistoryEntry(
        id: 'sc1',
        barcodeValue: '123456789',
        status: ScanMatchStatus.matched,
        matchedProductId: 'p1',
        matchedProductName: 'Test Product',
        scanIntent: 'sale',
        scannedBy: 'u1',
        scannedByName: 'User 1',
        timestamp: now,
        shopId: 's1',
      ),
    );
    await scanBox.close();


    final syncQueueBox = await Hive.openBox<SyncQueueItem>('sync_queue');
    await syncQueueBox.put(
      'sq1',
      SyncQueueItem(
        localId: 'sq1',
        shopId: 's1',
        userId: 'u1',
        operationType: SyncOperationType.createSale,
        entityType: 'sale',
        entityId: 'tx1',
        payload: {
          'total': 30.0,
          'createdAt': Timestamp.fromDate(now),
        },
        createdAt: now,
        updatedAt: now,
        status: SyncStatus.pending,
      ),
    );
    await syncQueueBox.close();

    final opsBox = await Hive.openBox<OperationJournalEntry>('local_operations');
    await opsBox.put(
      'op1',
      OperationJournalEntry(
        operationId: 'op1',
        shopId: 's1',
        operationType: 'sale',
        status: LocalOperationStatus.committed,
        createdAt: now,
        backupState: {'p1': {'quantity': 100}},
        targetMutations: {'p1': {'quantity': 98}},
      ),
    );
    await opsBox.close();

    // 2. NOW REOPEN EVERY SINGLE BOX FROM DISK
    final pReopen = await Hive.openBox<Product>('products');
    expect(pReopen.get('p1')?.name, 'Test Product');

    final cReopen = await Hive.openBox<Category>('categories');
    expect(cReopen.get('c1')?.name, 'Test Category');

    final sReopen = await Hive.openBox<SaleTransaction>('sales_transactions');
    expect(sReopen.get('tx1')?.total, 30.0);

    final smReopen = await Hive.openBox<StockMovement>('stock_movements');
    expect(smReopen.get('sm1')?.quantityChange, -2);

    final scReopen = await Hive.openBox<ScanHistoryEntry>('scan_history');
    expect(scReopen.get('sc1')?.barcodeValue, '123456789');

    final sqReopen = await Hive.openBox<SyncQueueItem>('sync_queue');
    expect(sqReopen.get('sq1')?.localId, 'sq1');

    final opReopen = await Hive.openBox<OperationJournalEntry>('local_operations');
    expect(opReopen.get('op1')?.operationId, 'op1');
  });

  test('Corrupted box on disk self-heals by resetting', () async {
    final corruptFile = File('${tempDir.path}/corrupt_box.hive');
    await corruptFile.writeAsBytes([0x01, 0x02, 0x03, 0x04]); // Invalid header / truncated bytes

    Box<dynamic> box;
    try {
      box = await Hive.openBox('corrupt_box');
    } catch (e) {
      // Self-healing flow
      await Hive.deleteBoxFromDisk('corrupt_box');
      box = await Hive.openBox('corrupt_box');
    }

    expect(box.isOpen, isTrue);
    await box.put('key1', 'val1');
    expect(box.get('key1'), 'val1');
    await box.close();
  });
}
