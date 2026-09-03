import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inventra/core/cache/hive_adapters.dart';
import 'package:inventra/core/cache/local_database.dart';
import 'package:inventra/core/connectivity/connectivity_service.dart';
import 'package:inventra/core/sync/sync_models.dart';
import 'package:inventra/core/sync/sync_processor.dart';
import 'package:inventra/features/inventory/data/repositories/offline_product_repository.dart';
import 'package:inventra/features/inventory/domain/entities/product.dart';
import 'package:inventra/features/scanner/data/scanner_repository.dart';
import 'package:inventra/shared/models/stock_movement.dart';

// ── Mocktail Definitions ──
// ignore: subtype_of_sealed_class
class MockFirestore extends Mock implements FirebaseFirestore {}
// ignore: subtype_of_sealed_class
class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}
// ignore: subtype_of_sealed_class
class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}
// ignore: subtype_of_sealed_class
class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}
// ignore: subtype_of_sealed_class
class MockQuery extends Mock implements Query<Map<String, dynamic>> {}
class MockFunctions extends Mock implements FirebaseFunctions {}
class MockHttpsCallable extends Mock implements HttpsCallable {}

// ── Controllable Connectivity Double ──
class ControllableConnectivityService extends ConnectivityService {
  bool _online = false;
  final _streamController = StreamController<bool>.broadcast();

  ControllableConnectivityService({bool initialOnline = false})
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

// ── Server Simulation State ──
class FakeServerBackend {
  final Map<String, Map<String, dynamic>> products = {};
  final Map<String, Map<String, dynamic>> transactions = {};
  final Map<String, Map<String, dynamic>> processedOperations = {};
  final List<String> executionOrder = [];

  bool simulateNetworkFailure = false;
  bool simulateCommitTimeout = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalDatabase localDb;
  late ControllableConnectivityService connectivity;
  late MockFirestore mockFirestore;
  late MockFunctions mockFunctions;
  late FakeServerBackend fakeBackend;
  late SyncProcessor processor;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_sync_integration_');
    Hive.init(tempDir.path);
    registerHiveAdapters();
    registerFallbackValue(SetOptions(merge: true));
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

    connectivity = ControllableConnectivityService(initialOnline: false);
    mockFirestore = MockFirestore();
    mockFunctions = MockFunctions();
    fakeBackend = FakeServerBackend();

    // ── Configure Mock Firestore collections & docs ──
    when(() => mockFirestore.collection(any())).thenAnswer((inv) {
      final mockCol = MockCollectionReference();

      final mockSnap = MockQuerySnapshot();
      when(() => mockSnap.docs).thenReturn([]);
      when(() => mockCol.get()).thenAnswer((_) async => mockSnap);

      final mockQuery = MockQuery();
      when(() => mockCol.orderBy(any(), descending: any(named: 'descending')))
          .thenReturn(mockQuery);
      when(() => mockQuery.limit(any())).thenReturn(mockQuery);
      when(() => mockQuery.get()).thenAnswer((_) async => mockSnap);

      when(() => mockCol.doc(any())).thenAnswer((docInv) {
        final docId = docInv.positionalArguments.isEmpty
            ? 'auto-id'
            : (docInv.positionalArguments[0] as String? ?? 'auto-id');
        final mockDoc = MockDocumentReference();

        when(() => mockDoc.set(any(), any())).thenAnswer((setInv) async {
          if (fakeBackend.simulateNetworkFailure) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'unavailable',
              message: 'Temporary network failure',
            );
          }
          final payload = Map<String, dynamic>.from(setInv.positionalArguments[0] as Map);
          fakeBackend.products[docId] = payload;
          fakeBackend.executionOrder.add(docId);
        });

        when(() => mockDoc.update(any())).thenAnswer((upInv) async {
          if (fakeBackend.simulateNetworkFailure) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'unavailable',
              message: 'Temporary network failure',
            );
          }
          final payload = Map<String, dynamic>.from(upInv.positionalArguments[0] as Map);
          fakeBackend.products[docId] = {
            ...?fakeBackend.products[docId],
            ...payload,
          };
          fakeBackend.executionOrder.add(docId);
        });

        return mockDoc;
      });

      return mockCol;
    });

    // ── Configure Mock Cloud Functions callables ──
    when(() => mockFunctions.httpsCallable(any())).thenAnswer((inv) {
      final name = inv.positionalArguments[0] as String;
      final mockCallable = MockHttpsCallable();

      when(() => mockCallable.call(any())).thenAnswer((callInv) async {
        if (fakeBackend.simulateNetworkFailure) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'Cloud Functions unavailable',
          );
        }

        final data = Map<String, dynamic>.from(callInv.positionalArguments[0] as Map? ?? {});
        final opId = data['operationId'] as String?;

        if (name == 'validateStockDeduction') {
          // Idempotency check
          if (opId != null && fakeBackend.processedOperations.containsKey(opId)) {
            final existing = fakeBackend.processedOperations[opId]!;
            return HttpsCallableResultFake({
              'transactionId': existing['transactionId'],
              'alreadyProcessed': true,
            });
          }

          final items = (data['items'] as List).cast<Map>();
          // Stock verification
          for (final item in items) {
            final pId = item['productId'] as String;
            final reqQty = (item['quantity'] as num).toInt();
            final currentStock =
                (fakeBackend.products[pId]?['quantity'] as num?)?.toInt() ?? 0;

            if (currentStock < reqQty) {
              throw FirebaseFunctionsException(
                code: 'failed-precondition',
                message: 'Insufficient stock for product. Available: $currentStock, Requested: $reqQty',
              );
            }
          }

          // Deduct stock
          for (final item in items) {
            final pId = item['productId'] as String;
            final reqQty = (item['quantity'] as num).toInt();
            final currentStock =
                (fakeBackend.products[pId]!['quantity'] as num).toInt();
            fakeBackend.products[pId]!['quantity'] = currentStock - reqQty;
          }

          final txId = opId ?? 'tx-srv-123';
          fakeBackend.transactions[txId] = data;
          fakeBackend.executionOrder.add(txId);

          if (opId != null) {
            fakeBackend.processedOperations[opId] = {
              'transactionId': txId,
              'data': data,
            };
          }

          if (fakeBackend.simulateCommitTimeout) {
            // Server committed, but network dropped before client received response
            throw FirebaseFunctionsException(
              code: 'deadline-exceeded',
              message: 'Client timeout after commit',
            );
          }

          return HttpsCallableResultFake({
            'transactionId': txId,
            'alreadyProcessed': false,
          });
        }

        if (name == 'processRestock') {
          final pId = data['productId'] as String;
          final qty = (data['quantity'] as num).toInt();
          final current = (fakeBackend.products[pId]?['quantity'] as num?)?.toInt() ?? 0;
          fakeBackend.products[pId] = {
            ...?fakeBackend.products[pId],
            'quantity': current + qty,
          };
          if (opId != null) fakeBackend.executionOrder.add(opId);
          return HttpsCallableResultFake({'success': true});
        }

        if (name == 'processStockAdjustment') {
          final pId = data['productId'] as String;
          final newQty = (data['newQuantity'] as num).toInt();
          fakeBackend.products[pId] = {
            ...?fakeBackend.products[pId],
            'quantity': newQty,
          };
          if (opId != null) fakeBackend.executionOrder.add(opId);
          return HttpsCallableResultFake({'success': true});
        }

        return HttpsCallableResultFake({});
      });

      return mockCallable;
    });

    processor = SyncProcessor(
      firestore: mockFirestore,
      functions: mockFunctions,
      localDb: localDb,
      connectivity: connectivity,
      initialShopId: 'shop-1',
    );
  });

  tearDown(() {
    connectivity.dispose();
    processor.dispose();
  });

  group('Production-Level Integration Test Matrix (Scenarios A - J)', () {
    // ═══════════════════════════════════════════
    // Test A: Offline product creation
    // ═══════════════════════════════════════════
    test('Scenario A: Offline product creation survives restart and syncs remotely', () async {
      connectivity.setOnline(false);
      final repo = OfflineProductRepository(
        localDb: localDb,
        syncProcessor: processor,
        firestore: mockFirestore,
        connectivity: connectivity,
      );

      final newProduct = Product(
        id: 'prod-A',
        name: 'Offline Energy Drink',
        sku: 'NRG-001',
        costPrice: 500,
        sellingPrice: 800,
        quantity: 50,
        reorderLevel: 10,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'user-1',
        updatedBy: 'user-1',
      );

      // 1. Create product offline through repository
      await repo.addProduct('shop-1', newProduct);

      // 2. Immediately visible in local cache
      expect(localDb.productsBox.get('prod-A')?.name, 'Offline Energy Drink');

      // 3. Sync queue contains createProduct
      expect(
        localDb.syncQueueBox.values.any((i) =>
            i.operationType == SyncOperationType.createProduct &&
            i.entityId == 'prod-A'),
        isTrue,
      );

      // 4. Survives repository recreation
      final repo2 = OfflineProductRepository(
        localDb: localDb,
        syncProcessor: processor,
        connectivity: connectivity,
      );
      final fetched = await repo2.getProduct('shop-1', 'prod-A');
      expect(fetched?.name, 'Offline Energy Drink');

      // 5. Restore internet & synchronize
      connectivity.setOnline(true);
      await processor.processQueue();

      // 6. Remotely synchronized
      expect(fakeBackend.products['prod-A']?['name'], 'Offline Energy Drink');
      // 7. Queue entry cleared
      expect(localDb.syncQueueBox.isEmpty, isTrue);
    });

    // ═══════════════════════════════════════════
    // Test B: Offline create + update
    // ═══════════════════════════════════════════
    test('Scenario B: Offline create + update resolves dependencies deterministically', () async {
      connectivity.setOnline(false);
      final repo = OfflineProductRepository(
        localDb: localDb,
        syncProcessor: processor,
        connectivity: connectivity,
      );

      final initial = Product(
        id: 'prod-B',
        name: 'Initial Name',
        sku: 'SKU-B',
        costPrice: 100,
        sellingPrice: 200,
        quantity: 20,
        reorderLevel: 5,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'user-1',
        updatedBy: 'user-1',
      );

      await repo.addProduct('shop-1', initial);
      await repo.updateProduct('shop-1', initial.copyWith(name: 'Updated Name', sellingPrice: 250));

      final queueItems = localDb.syncQueueBox.values.toList();
      expect(queueItems.length, 2);
      final createItem = queueItems.firstWhere((i) => i.operationType == SyncOperationType.createProduct);
      final updateItem = queueItems.firstWhere((i) => i.operationType == SyncOperationType.updateProduct);

      // Verify explicit dependency was recorded
      expect(updateItem.allDependencies, contains(createItem.localId));

      connectivity.setOnline(true);
      await processor.processQueue();

      // Verify server execution order: Create first, then Update
      expect(fakeBackend.executionOrder, ['prod-B', 'prod-B']);
      expect(fakeBackend.products['prod-B']?['name'], 'Updated Name');
      expect(fakeBackend.products['prod-B']?['sellingPrice'], 250);
      expect(localDb.syncQueueBox.isEmpty, isTrue);
    });

    // ═══════════════════════════════════════════
    // Test C: Offline product + restock
    // ═══════════════════════════════════════════
    test('Scenario C: Offline product + restock executes CREATE before RESTOCK', () async {
      connectivity.setOnline(false);
      final repo = OfflineProductRepository(
        localDb: localDb,
        syncProcessor: processor,
        connectivity: connectivity,
      );

      final product = Product(
        id: 'prod-C',
        name: 'Juice Box',
        sku: 'JB-001',
        costPrice: 150,
        sellingPrice: 300,
        quantity: 10,
        reorderLevel: 5,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'user-1',
        updatedBy: 'user-1',
      );

      await repo.addProduct('shop-1', product);
      await repo.restockWithRecord(
        shopId: 'shop-1',
        productId: 'prod-C',
        productName: 'Juice Box',
        quantity: 15,
        userId: 'user-1',
      );

      // Local stock immediately updated
      expect(localDb.productsBox.get('prod-C')?.quantity, 25);

      connectivity.setOnline(true);
      await processor.processQueue();

      expect(fakeBackend.products['prod-C']?['quantity'], 25);
      expect(localDb.syncQueueBox.isEmpty, isTrue);
    });

    // ═══════════════════════════════════════════
    // Test D: Offline product + sale
    // ═══════════════════════════════════════════
    test('Scenario D: Offline product + sale executes CREATE before SALE', () async {
      connectivity.setOnline(false);
      final productRepo = OfflineProductRepository(
        localDb: localDb,
        syncProcessor: processor,
        connectivity: connectivity,
      );
      final scannerRepo = ScannerRepository(
        localDb: localDb,
        syncProcessor: processor,
      );

      final product = Product(
        id: 'prod-D',
        name: 'Malt Drink',
        sku: 'MLT-001',
        costPrice: 200,
        sellingPrice: 400,
        quantity: 20,
        reorderLevel: 5,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: 'user-1',
        updatedBy: 'user-1',
      );

      await productRepo.addProduct('shop-1', product);
      final txId = await scannerRepo.performMultiItemSale(
        shopId: 'shop-1',
        items: [
          {'productId': 'prod-D', 'quantity': 3, 'unitPrice': 400.0}
        ],
        userId: 'user-1',
        userName: 'Cashier',
      );

      // Local stock decreased to 17
      expect(localDb.productsBox.get('prod-D')?.quantity, 17);
      expect(localDb.salesTransactionsBox.get(txId)?.status, TransactionStatus.completedLocal);

      connectivity.setOnline(true);
      await processor.processQueue();

      // Create executed before sale
      expect(fakeBackend.executionOrder, ['prod-D', txId]);
      expect(fakeBackend.transactions[txId], isNotNull);
      expect(localDb.syncQueueBox.isEmpty, isTrue);
      expect(localDb.salesTransactionsBox.get(txId)?.status, TransactionStatus.synced);
    });

    // ═══════════════════════════════════════════
    // Test E: Failed sync recovery
    // ═══════════════════════════════════════════
    test('Scenario E: Transient network failure preserves pending status and recovers on retry', () async {
      connectivity.setOnline(false); // Add offline first

      final repo = OfflineProductRepository(
        localDb: localDb,
        syncProcessor: processor,
        connectivity: connectivity,
      );

      await repo.addProduct(
        'shop-1',
        Product(
          id: 'prod-E',
          name: 'Failing Item',
          sku: 'FAIL-1',
          costPrice: 10,
          sellingPrice: 20,
          quantity: 5,
          reorderLevel: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          createdBy: 'user-1',
          updatedBy: 'user-1',
        ),
      );

      // Connect, but server experiences network failure
      connectivity.setOnline(true);
      fakeBackend.simulateNetworkFailure = true;
      await processor.processQueue();

      // Transient failure scheduled retry
      final queued = localDb.syncQueueBox.values.first;
      expect(queued.status, SyncStatus.pending);
      expect(queued.retryCount, 1);

      // Server recovers
      fakeBackend.simulateNetworkFailure = false;
      await processor.processQueue();

      expect(localDb.syncQueueBox.isEmpty, isTrue);
      expect(fakeBackend.products['prod-E'], isNotNull);
    });

    // ═══════════════════════════════════════════
    // Test F: Server commit + client timeout (Idempotency)
    // ═══════════════════════════════════════════
    test('Scenario F: Server commit + client timeout uses operationId to prevent duplicate deduction', () async {
      connectivity.setOnline(false); // Offline during sale creation
      final scannerRepo = ScannerRepository(
        localDb: localDb,
        syncProcessor: processor,
      );

      // Pre-set product with 50 stock in both local database and server
      await localDb.productsBox.put(
        'prod-F',
        Product(
          id: 'prod-F',
          name: 'Idempotent Biscuit',
          sku: 'BIS-1',
          costPrice: 50,
          sellingPrice: 100,
          quantity: 50,
          reorderLevel: 5,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          createdBy: 'user-1',
          updatedBy: 'user-1',
        ),
      );
      fakeBackend.products['prod-F'] = {'quantity': 50};

      // 1. Queue sale while server is set to simulate timeout after commit
      fakeBackend.simulateCommitTimeout = true;
      final txId = await scannerRepo.performMultiItemSale(
        shopId: 'shop-1',
        items: [
          {'productId': 'prod-F', 'quantity': 2, 'unitPrice': 100.0}
        ],
        userId: 'user-1',
        userName: 'Cashier',
      );

      // 2. Reconnect and attempt sync (will commit on server, but client times out)
      connectivity.setOnline(true);
      await processor.processQueue();

      // Server processed deduction once: 50 -> 48
      expect(fakeBackend.products['prod-F']?['quantity'], 48);

      // Client retries with same operationId (txId)
      fakeBackend.simulateCommitTimeout = false;
      await processor.processQueue();

      // Deducted only ONCE, not twice!
      expect(fakeBackend.products['prod-F']?['quantity'], 48);
      expect(fakeBackend.processedOperations.containsKey(txId), isTrue);
      expect(fakeBackend.processedOperations.length, 1);
      expect(localDb.syncQueueBox.isEmpty, isTrue);
    });

    // ═══════════════════════════════════════════
    // Test G: Stock conflict
    // ═══════════════════════════════════════════
    test('Scenario G: Insufficient server stock records conflict, keeps local tx, notifies user', () async {
      connectivity.setOnline(false);
      final scannerRepo = ScannerRepository(
        localDb: localDb,
        syncProcessor: processor,
      );

      await localDb.productsBox.put(
        'prod-G',
        Product(
          id: 'prod-G',
          name: 'Limited Edition Sneakers',
          sku: 'SNK-1',
          costPrice: 5000,
          sellingPrice: 10000,
          quantity: 5,
          reorderLevel: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          createdBy: 'user-1',
          updatedBy: 'user-1',
        ),
      );

      // Server only has 1 in stock!
      fakeBackend.products['prod-G'] = {'quantity': 1};

      final txId = await scannerRepo.performMultiItemSale(
        shopId: 'shop-1',
        items: [
          {'productId': 'prod-G', 'quantity': 4, 'unitPrice': 10000.0}
        ],
        userId: 'user-1',
        userName: 'Cashier',
      );

      connectivity.setOnline(true);
      await processor.processQueue();

      final queued = localDb.syncQueueBox.get(txId);
      expect(queued, isNotNull);
      expect(queued!.status, SyncStatus.conflict);
      expect(queued.conflictCategory, SyncConflictCategory.stockConflict);
      expect(queued.conflictExplanation, contains('Insufficient stock'));

      // Local transaction is preserved with conflict status
      final localTx = localDb.salesTransactionsBox.get(txId);
      expect(localTx, isNotNull);
      expect(localTx!.status, 'conflict');

      // Engine state reflects conflict
      expect(processor.currentState, SyncEngineState.conflict);
    });

    // ═══════════════════════════════════════════
    // Test H: Stale processing recovery
    // ═══════════════════════════════════════════
    test('Scenario H: Stale processing operation is recovered to pending on startup', () async {
      final staleItem = SyncQueueItem(
        localId: 'stale-op-1',
        shopId: 'shop-1',
        userId: 'user-1',
        operationType: SyncOperationType.createProduct,
        entityType: 'product',
        entityId: 'prod-H',
        payload: {'name': 'Recovered Item'},
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        status: SyncStatus.processing,
        processingStartedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await localDb.syncQueueBox.put(staleItem.localId, staleItem);

      final recovered = processor.recoverStaleProcessingItems(threshold: const Duration(seconds: 30));
      expect(recovered, 1);

      final item = localDb.syncQueueBox.get('stale-op-1');
      expect(item?.status, SyncStatus.pending);
      expect(item?.processingStartedAt, isNull);

      connectivity.setOnline(true);
      await processor.processQueue();
      expect(localDb.syncQueueBox.isEmpty, isTrue);
    });

    // ═══════════════════════════════════════════
    // Test I: Dependency cycle detection
    // ═══════════════════════════════════════════
    test('Scenario I: Dependency cycle is detected and marked conflict without infinite loop', () async {
      final itemA = SyncQueueItem(
        localId: 'op-A',
        shopId: 'shop-1',
        userId: 'u1',
        operationType: SyncOperationType.updateProduct,
        entityType: 'product',
        payload: const {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dependsOnOperationIds: const ['op-B'],
      );
      final itemB = SyncQueueItem(
        localId: 'op-B',
        shopId: 'shop-1',
        userId: 'u1',
        operationType: SyncOperationType.updateProduct,
        entityType: 'product',
        payload: const {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dependsOnOperationIds: const ['op-C'],
      );
      final itemC = SyncQueueItem(
        localId: 'op-C',
        shopId: 'shop-1',
        userId: 'u1',
        operationType: SyncOperationType.updateProduct,
        entityType: 'product',
        payload: const {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dependsOnOperationIds: const ['op-A'],
      );

      await localDb.syncQueueBox.put(itemA.localId, itemA);
      await localDb.syncQueueBox.put(itemB.localId, itemB);
      await localDb.syncQueueBox.put(itemC.localId, itemC);

      connectivity.setOnline(true);
      await processor.processQueue();

      expect(localDb.syncQueueBox.get('op-A')?.status, SyncStatus.conflict);
      expect(localDb.syncQueueBox.get('op-B')?.status, SyncStatus.conflict);
      expect(localDb.syncQueueBox.get('op-C')?.status, SyncStatus.conflict);
      expect(localDb.syncQueueBox.get('op-A')?.conflictExplanation, contains('Circular'));
    });

    // ═══════════════════════════════════════════
    // Test J: Shop isolation
    // ═══════════════════════════════════════════
    test('Scenario J: Shop isolation ensures Shop A operations are not processed for Shop B', () async {
      connectivity.setOnline(false);
      processor.setActiveShop('shop-B');

      final itemShopA = SyncQueueItem(
        localId: 'op-shop-A',
        shopId: 'shop-A',
        userId: 'u1',
        operationType: SyncOperationType.createProduct,
        entityType: 'product',
        entityId: 'prod-A-tenant',
        payload: {'name': 'Shop A Product'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final itemShopB = SyncQueueItem(
        localId: 'op-shop-B',
        shopId: 'shop-B',
        userId: 'u2',
        operationType: SyncOperationType.createProduct,
        entityType: 'product',
        entityId: 'prod-B-tenant',
        payload: {'name': 'Shop B Product'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await localDb.syncQueueBox.put(itemShopA.localId, itemShopA);
      await localDb.syncQueueBox.put(itemShopB.localId, itemShopB);

      connectivity.setOnline(true);
      await processor.processQueue();

      // Shop B processed and removed
      expect(localDb.syncQueueBox.get('op-shop-B'), isNull);
      expect(fakeBackend.products['prod-B-tenant'], isNotNull);

      // Shop A untouched in queue
      expect(localDb.syncQueueBox.get('op-shop-A'), isNotNull);
      expect(fakeBackend.products['prod-A-tenant'], isNull);

      // Switch to Shop A
      processor.setActiveShop('shop-A');
      await processor.processQueue();

      expect(localDb.syncQueueBox.get('op-shop-A'), isNull);
      expect(fakeBackend.products['prod-A-tenant'], isNotNull);
    });
  });
}

// ── Test Double for HttpsCallableResult ──
class HttpsCallableResultFake implements HttpsCallableResult<dynamic> {
  @override
  final dynamic data;

  HttpsCallableResultFake(this.data);
}
