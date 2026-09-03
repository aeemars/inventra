import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inventra/core/cache/hive_adapters.dart';
import 'package:inventra/core/cache/local_database.dart';
import 'package:inventra/core/connectivity/connectivity_service.dart';
import 'package:inventra/core/constants/firestore_paths.dart';
import 'package:inventra/core/sync/sync_models.dart';
import 'package:inventra/core/sync/sync_processor.dart';
import 'package:inventra/features/inventory/domain/entities/product.dart';
import 'package:inventra/shared/models/stock_movement.dart';

// ── Mocktail Definitions ──
// ignore: subtype_of_sealed_class
class MockFirestore extends Mock implements FirebaseFirestore {}
// ignore: subtype_of_sealed_class
class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}
// ignore: subtype_of_sealed_class
class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}
// ignore: subtype_of_sealed_class
class MockQueryDocumentSnapshot extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}
// ignore: subtype_of_sealed_class
class MockQuery extends Mock implements Query<Map<String, dynamic>> {}

// ── Controllable Connectivity Double ──
class ControllableConnectivityService extends ConnectivityService {
  bool _online = true;
  final _streamController = StreamController<bool>.broadcast();

  ControllableConnectivityService({bool initialOnline = true})
      : _online = initialOnline;

  @override
  bool get isOnline => _online;

  @override
  bool get isOffline => !_online;

  @override
  Stream<bool> get onConnectivityChanged => _streamController.stream;

  void setOnline(bool online) {
    _online = online;
    _streamController.add(online);
  }

  @override
  Future<bool> checkConnection() async => _online;

  @override
  void dispose() {
    _streamController.close();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalDatabase localDb;
  late ControllableConnectivityService connectivity;
  late MockFirestore mockFirestore;
  late SyncProcessor processor;

  const testShopId = 'shop-remote-sync-test';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_remote_sync_test_');
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
    await localDb.clearShopData();

    connectivity = ControllableConnectivityService(initialOnline: true);
    mockFirestore = MockFirestore();

    processor = SyncProcessor(
      firestore: mockFirestore,
      localDb: localDb,
      connectivity: connectivity,
      initialShopId: testShopId,
    );
  });

  tearDown(() {
    processor.dispose();
    connectivity.dispose();
  });

  MockQueryDocumentSnapshot createDocMock(
    String id,
    Map<String, dynamic> data,
  ) {
    final doc = MockQueryDocumentSnapshot();
    when(() => doc.id).thenReturn(id);
    when(() => doc.data()).thenReturn(data);
    return doc;
  }

  MockQuerySnapshot createSnapMock(List<MockQueryDocumentSnapshot> docs) {
    final snap = MockQuerySnapshot();
    when(() => snap.docs).thenReturn(docs);
    return snap;
  }

  void setupEmptyRemoteCollections() {
    final emptySnap = createSnapMock([]);

    final prodCol = MockCollectionReference();
    final prodQuery = MockQuery();
    when(() => mockFirestore.collection(FirestorePaths.products(testShopId)))
        .thenReturn(prodCol);
    when(() => prodCol.limit(any())).thenReturn(prodQuery);
    when(() => prodQuery.get()).thenAnswer((_) async => emptySnap);
    when(() => prodCol.where('updatedAt', isGreaterThan: any(named: 'isGreaterThan')))
        .thenReturn(prodQuery);
    when(() => prodQuery.orderBy('updatedAt')).thenReturn(prodQuery);

    final catCol = MockCollectionReference();
    final catQuery = MockQuery();
    when(() => mockFirestore.collection(FirestorePaths.categories(testShopId)))
        .thenReturn(catCol);
    when(() => catCol.limit(any())).thenReturn(catQuery);
    when(() => catQuery.get()).thenAnswer((_) async => emptySnap);
    when(() => catCol.where('updatedAt', isGreaterThan: any(named: 'isGreaterThan')))
        .thenReturn(catQuery);
    when(() => catQuery.orderBy('updatedAt')).thenReturn(catQuery);

    final txCol = MockCollectionReference();
    final txQuery = MockQuery();
    when(() => mockFirestore.collection(FirestorePaths.transactions(testShopId)))
        .thenReturn(txCol);
    when(() => txCol.orderBy('createdAt', descending: any(named: 'descending')))
        .thenReturn(txQuery);
    when(() => txCol.where('createdAt', isGreaterThan: any(named: 'isGreaterThan')))
        .thenReturn(txQuery);
    when(() => txQuery.limit(any())).thenReturn(txQuery);
    when(() => txQuery.orderBy('createdAt')).thenReturn(txQuery);
    when(() => txQuery.get()).thenAnswer((_) async => emptySnap);

    final smCol = MockCollectionReference();
    final smQuery = MockQuery();
    when(() => mockFirestore.collection(FirestorePaths.stockMovements(testShopId)))
        .thenReturn(smCol);
    when(() => smCol.orderBy('createdAt', descending: any(named: 'descending')))
        .thenReturn(smQuery);
    when(() => smCol.where('createdAt', isGreaterThan: any(named: 'isGreaterThan')))
        .thenReturn(smQuery);
    when(() => smQuery.limit(any())).thenReturn(smQuery);
    when(() => smQuery.orderBy('createdAt')).thenReturn(smQuery);
    when(() => smQuery.get()).thenAnswer((_) async => emptySnap);

    final shCol = MockCollectionReference();
    final shQuery = MockQuery();
    when(() => mockFirestore.collection(FirestorePaths.scanHistory(testShopId)))
        .thenReturn(shCol);
    when(() => shCol.orderBy('timestamp', descending: any(named: 'descending')))
        .thenReturn(shQuery);
    when(() => shCol.where('timestamp', isGreaterThan: any(named: 'isGreaterThan')))
        .thenReturn(shQuery);
    when(() => shQuery.limit(any())).thenReturn(shQuery);
    when(() => shQuery.orderBy('timestamp')).thenReturn(shQuery);
    when(() => shQuery.get()).thenAnswer((_) async => emptySnap);
  }

  test('Initial Full Sync populates all Hive boxes and establishes checkpoint', () async {
    setupEmptyRemoteCollections();

    final now = DateTime.now();
    final ts = Timestamp.fromDate(now);

    // Mock 1 Product
    final prodDoc = createDocMock('prod-1', {
      'name': 'Wireless Mouse',
      'barcode': '12345678',
      'costPrice': 15.0,
      'sellingPrice': 25.0,
      'quantity': 42,
      'lowStockThreshold': 5,
      'category': 'Electronics',
      'isActive': true,
      'shopId': testShopId,
      'createdAt': ts,
      'updatedAt': ts,
    });
    final prodCol = mockFirestore.collection(FirestorePaths.products(testShopId));
    final prodQuery = prodCol.limit(250);
    when(() => prodQuery.get()).thenAnswer((_) async => createSnapMock([prodDoc]));

    // Mock 1 Category
    final catDoc = createDocMock('cat-1', {
      'name': 'Electronics',
      'description': 'Electronic gadgets and accessories',
      'productCount': 1,
      'createdAt': ts,
      'updatedAt': ts,
    });
    final catCol = mockFirestore.collection(FirestorePaths.categories(testShopId));
    final catQuery = catCol.limit(100);
    when(() => catQuery.get()).thenAnswer((_) async => createSnapMock([catDoc]));

    // Execute pull
    await processor.pullRemoteChanges(testShopId);

    // Verify local database state
    expect(localDb.productsBox.containsKey('prod-1'), isTrue);
    final p = localDb.productsBox.get('prod-1')!;
    expect(p.name, equals('Wireless Mouse'));
    expect(p.quantity, equals(42));

    expect(localDb.categoriesBox.containsKey('cat-1'), isTrue);
    final c = localDb.categoriesBox.get('cat-1')!;
    expect(c.name, equals('Electronics'));

    // Verify sync metadata checkpoint
    final meta = processor.getSyncMetadata(testShopId);
    expect(meta, isNotNull);
    expect(meta!.lastProductSyncAt, isNotNull);
    expect(meta.lastCategorySyncAt, isNotNull);
    expect(meta.lastSuccessfulSyncAt, isNotNull);
  });

  test('Incremental Sync only queries updates since last checkpoint', () async {
    setupEmptyRemoteCollections();

    final t1 = DateTime.now().subtract(const Duration(hours: 2));
    final t2 = DateTime.now().subtract(const Duration(minutes: 30));

    // Establish prior checkpoint
    final priorMeta = SyncMetadata(
      shopId: testShopId,
      lastProductSyncAt: t1,
    );
    await localDb.syncMetadataBox.put('sync_checkpoint_$testShopId', priorMeta.toMap());

    // Setup incremental mock query
    final prodCol = mockFirestore.collection(FirestorePaths.products(testShopId));
    final incrementalQuery = MockQuery();
    when(() => prodCol.where('updatedAt', isGreaterThan: any(named: 'isGreaterThan')))
        .thenReturn(incrementalQuery);
    when(() => incrementalQuery.orderBy('updatedAt')).thenReturn(incrementalQuery);

    final updatedDoc = createDocMock('prod-1', {
      'name': 'Wireless Mouse Pro',
      'barcode': '12345678',
      'costPrice': 18.0,
      'sellingPrice': 30.0,
      'quantity': 50,
      'lowStockThreshold': 5,
      'category': 'Electronics',
      'isActive': true,
      'shopId': testShopId,
      'createdAt': Timestamp.fromDate(t1),
      'updatedAt': Timestamp.fromDate(t2),
    });
    when(() => incrementalQuery.get())
        .thenAnswer((_) async => createSnapMock([updatedDoc]));

    await processor.pullRemoteChanges(testShopId);

    // Verify incremental query was used
    verify(() => prodCol.where('updatedAt', isGreaterThan: Timestamp.fromDate(t1))).called(1);

    // Verify product updated locally
    final p = localDb.productsBox.get('prod-1')!;
    expect(p.name, equals('Wireless Mouse Pro'));
    expect(p.quantity, equals(50));

    // Verify checkpoint advanced to t2
    final updatedMeta = processor.getSyncMetadata(testShopId);
    expect(updatedMeta!.lastProductSyncAt?.millisecondsSinceEpoch,
        equals(t2.millisecondsSinceEpoch));
  });

  test('Conflict Protection: preserves projected stock during local pending sale', () async {
    setupEmptyRemoteCollections();

    final now = DateTime.now();
    final ts = Timestamp.fromDate(now);

    // 1. Initial product has 20 units locally
    final initialProduct = Product(
      id: 'prod-stock-test',
      name: 'Mechanical Keyboard',
      sku: 'KB-01',
      barcode: '99887766',
      costPrice: 50.0,
      sellingPrice: 80.0,
      quantity: 15, // local stock after deducting 5 offline
      reorderLevel: 5,
      createdAt: now,
      updatedAt: now,
      createdBy: 'user-1',
      updatedBy: 'user-1',
    );
    await localDb.productsBox.put('prod-stock-test', initialProduct);

    // 2. Queue contains a pending sale of 5 units
    final pendingSaleItem = SyncQueueItem(
      localId: 'op-sale-1',
      shopId: testShopId,
      userId: 'user-1',
      operationType: SyncOperationType.createSale,
      entityType: 'sale',
      entityId: 'local-tx-1',
      payload: {
        'items': [
          {'productId': 'prod-stock-test', 'quantity': 5, 'unitPrice': 80.0}
        ],
        'total': 400.0,
      },
      createdAt: now,
      updatedAt: now,
      status: SyncStatus.pending,
    );
    await localDb.syncQueueBox.put('op-sale-1', pendingSaleItem);

    // 3. Remote server has stock = 20 (it hasn't received the sale yet)
    final remoteDoc = createDocMock('prod-stock-test', {
      'name': 'Mechanical Keyboard',
      'barcode': '99887766',
      'costPrice': 50.0,
      'sellingPrice': 80.0,
      'quantity': 20, // Remote server's current stock
      'lowStockThreshold': 5,
      'isActive': true,
      'shopId': testShopId,
      'createdAt': ts,
      'updatedAt': ts,
    });

    final prodCol = mockFirestore.collection(FirestorePaths.products(testShopId));
    final prodQuery = prodCol.limit(250);
    when(() => prodQuery.get()).thenAnswer((_) async => createSnapMock([remoteDoc]));

    // 4. Run pullRemoteChanges
    await processor.pullRemoteChanges(testShopId);

    // 5. Verify local stock is reconciled as remote(20) + localPendingDelta(-5) = 15
    final p = localDb.productsBox.get('prod-stock-test')!;
    expect(p.quantity, equals(15),
        reason: 'Local projected stock must NOT be overwritten by stale remote stock');
  });

  test('Transaction Reconciliation: matches local pending sale without duplicating', () async {
    setupEmptyRemoteCollections();

    final now = DateTime.now();

    // 1. Client has a local transaction marked as synced with serverTransactionId 'srv-tx-100'
    final localSaleTx = SaleTransaction(
      id: 'local-tx-uuid-1',
      type: 'sale',
      items: const [],
      subtotal: 100.0,
      discount: 0.0,
      taxAmount: 0.0,
      total: 100.0,
      paymentMethod: 'cash',
      status: 'synced',
      createdBy: 'user-1',
      createdByName: 'Cashier One',
      createdAt: now,
      serverTransactionId: 'srv-tx-100',
    );
    await localDb.salesTransactionsBox.put('local-tx-uuid-1', localSaleTx);

    // 2. Server emits the transaction doc 'srv-tx-100'
    final txDoc = createDocMock('srv-tx-100', {
      'type': 'sale',
      'items': [],
      'subtotal': 100.0,
      'discount': 0.0,
      'taxAmount': 0.0,
      'total': 100.0,
      'paymentMethod': 'cash',
      'status': 'completed',
      'createdBy': 'user-1',
      'createdByName': 'Cashier One',
      'createdAt': Timestamp.fromDate(now),
    });

    final txCol = mockFirestore.collection(FirestorePaths.transactions(testShopId));
    final txQuery = MockQuery();
    when(() => txCol.orderBy('createdAt', descending: true)).thenReturn(txQuery);
    when(() => txQuery.limit(50)).thenReturn(txQuery);
    when(() => txQuery.get()).thenAnswer((_) async => createSnapMock([txDoc]));

    // 3. Run pull
    await processor.pullRemoteChanges(testShopId);

    // 4. Verify no second transaction was inserted
    expect(localDb.salesTransactionsBox.length, equals(1));
    final tx = localDb.salesTransactionsBox.get('local-tx-uuid-1')!;
    expect(tx.serverTransactionId, equals('srv-tx-100'));
    expect(tx.status, equals('synced'));
  });

  test('Multi-Tenant Isolation: does not sync if shop is inactive', () async {
    setupEmptyRemoteCollections();

    // Set active shop to a different shop
    processor.setActiveShop('shop-other');

    // Attempt pull on testShopId
    await processor.pullRemoteChanges(testShopId);

    // No products should be pulled for inactive shop
    expect(localDb.productsBox.isEmpty, isTrue);
  });
}
