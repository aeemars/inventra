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
import 'package:inventra/shared/models/stock_movement.dart';

// ignore: subtype_of_sealed_class
class MockFirestore extends Mock implements FirebaseFirestore {}
// ignore: subtype_of_sealed_class
class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}
// ignore: subtype_of_sealed_class
class MockHttpsCallable extends Mock implements HttpsCallable {}
// ignore: subtype_of_sealed_class
class MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

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
  late MockFirebaseFunctions mockFunctions;
  late MockHttpsCallable mockCallable;
  late SyncProcessor processor;

  const testShopId = 'shop_tx_status_test';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_tx_status_test_');
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

    connectivity = ControllableConnectivityService(initialOnline: true);
    mockFirestore = MockFirestore();
    mockFunctions = MockFirebaseFunctions();
    mockCallable = MockHttpsCallable();

    when(() => mockFunctions.httpsCallable(any())).thenReturn(mockCallable);

    processor = SyncProcessor(
      firestore: mockFirestore,
      functions: mockFunctions,
      localDb: localDb,
      connectivity: connectivity,
      initialShopId: testShopId,
    );
  });

  tearDown(() {
    processor.dispose();
    connectivity.dispose();
  });

  group('Reliable Transaction Status Lifecycle', () {
    test('Successful sync transitions completed_local -> syncing -> synced with server metadata', () async {
      final now = DateTime.now();
      const txId = 'tx_success_001';

      // 1. Locally completed transaction
      final localTx = SaleTransaction(
        id: txId,
        shopId: testShopId,
        type: 'sale',
        items: const [
          SaleItem(
            productId: 'p1',
            productName: 'P1',
            sku: 'SKU1',
            quantity: 2,
            unitPrice: 15.0,
            totalPrice: 30.0,
          )
        ],
        subtotal: 30.0,
        discount: 0.0,
        taxAmount: 0.0,
        total: 30.0,
        paymentMethod: 'cash',
        status: TransactionStatus.completedLocal,
        createdBy: 'user_1',
        createdByName: 'Alice',
        createdAt: now,
      );
      await localDb.putTransaction(testShopId, localTx);

      // Verify status is completed_local initially, NOT synced
      expect(localDb.getTransaction(testShopId, txId)?.status, TransactionStatus.completedLocal);

      // 2. Queue mutation
      final syncItem = SyncQueueItem(
        localId: txId,
        shopId: testShopId,
        userId: 'user_1',
        operationType: SyncOperationType.createSale,
        entityType: 'sale',
        entityId: txId,
        payload: {
          'items': [
            {'productId': 'p1', 'quantity': 2, 'unitPrice': 15.0}
          ],
          'paymentMethod': 'cash',
          'discount': 0.0,
        },
        createdAt: now,
        updatedAt: now,
      );
      await localDb.syncQueueBox.put(txId, syncItem);

      // Mock successful server callable response
      final mockResult = MockHttpsCallableResult();
      when(() => mockResult.data).thenReturn({
        'success': true,
        'transactionId': 'server_tx_abc_789',
      });
      when(() => mockCallable.call(any())).thenAnswer((_) async => mockResult);

      // 3. Process queue
      await processor.processQueue();

      // 4. Verify transaction transitioned to 'synced' with server transaction ID and timestamp
      final syncedTx = localDb.getTransaction(testShopId, txId);
      expect(syncedTx, isNotNull);
      expect(syncedTx!.status, TransactionStatus.synced);
      expect(syncedTx.serverTransactionId, 'server_tx_abc_789');
      expect(syncedTx.syncedAt, isNotNull);
      expect(syncedTx.syncError, isNull);

      // Verify queue item removed upon success
      expect(localDb.syncQueueBox.containsKey(txId), isFalse);
    });

    test('Business conflict transitions transaction to conflict with syncError', () async {
      final now = DateTime.now();
      const txId = 'tx_conflict_002';

      final localTx = SaleTransaction(
        id: txId,
        shopId: testShopId,
        type: 'sale',
        items: const [
          SaleItem(
            productId: 'p_out_of_stock',
            productName: 'Out of stock item',
            sku: 'OOS-1',
            quantity: 5,
            unitPrice: 20.0,
            totalPrice: 100.0,
          )
        ],
        subtotal: 100.0,
        discount: 0.0,
        taxAmount: 0.0,
        total: 100.0,
        paymentMethod: 'cash',
        status: TransactionStatus.completedLocal,
        createdBy: 'user_1',
        createdByName: 'Alice',
        createdAt: now,
      );
      await localDb.putTransaction(testShopId, localTx);

      final syncItem = SyncQueueItem(
        localId: txId,
        shopId: testShopId,
        userId: 'user_1',
        operationType: SyncOperationType.createSale,
        entityType: 'sale',
        entityId: txId,
        payload: {
          'items': [
            {'productId': 'p_out_of_stock', 'quantity': 5}
          ],
          'paymentMethod': 'cash',
          'discount': 0.0,
        },
        createdAt: now,
        updatedAt: now,
      );
      await localDb.syncQueueBox.put(txId, syncItem);

      // Mock server throwing stock conflict
      when(() => mockCallable.call(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Insufficient stock remaining on server',
        ),
      );

      await processor.processQueue();

      // Verify transaction is marked 'conflict' with structured error
      final conflictedTx = localDb.getTransaction(testShopId, txId);
      expect(conflictedTx, isNotNull);
      expect(conflictedTx!.status, TransactionStatus.conflict);
      expect(conflictedTx.syncError, contains('Insufficient stock'));

      // Queue item remains in conflict state
      final queueEntry = localDb.syncQueueBox.get(txId);
      expect(queueEntry, isNotNull);
      expect(queueEntry!.status, SyncStatus.conflict);
    });

    test('Transient network failure transitions transaction to sync_failed', () async {
      final now = DateTime.now();
      const txId = 'tx_transient_003';

      final localTx = SaleTransaction(
        id: txId,
        shopId: testShopId,
        type: 'sale',
        items: const [
          SaleItem(
            productId: 'p1',
            productName: 'P1',
            sku: 'SKU-1',
            quantity: 1,
            unitPrice: 10.0,
            totalPrice: 10.0,
          )
        ],
        subtotal: 10.0,
        discount: 0.0,
        taxAmount: 0.0,
        total: 10.0,
        paymentMethod: 'cash',
        status: TransactionStatus.completedLocal,
        createdBy: 'user_1',
        createdByName: 'Alice',
        createdAt: now,
      );
      await localDb.putTransaction(testShopId, localTx);

      final syncItem = SyncQueueItem(
        localId: txId,
        shopId: testShopId,
        userId: 'user_1',
        operationType: SyncOperationType.createSale,
        entityType: 'sale',
        entityId: txId,
        payload: {
          'items': [
            {'productId': 'p1', 'quantity': 1}
          ],
          'paymentMethod': 'cash',
          'discount': 0.0,
        },
        createdAt: now,
        updatedAt: now,
      );
      await localDb.syncQueueBox.put(txId, syncItem);

      // Mock socket exception / timeout
      when(() => mockCallable.call(any())).thenThrow(
        const SocketException('Connection timed out'),
      );

      await processor.processQueue();

      final failedTx = localDb.getTransaction(testShopId, txId);
      expect(failedTx, isNotNull);
      expect(failedTx!.status, TransactionStatus.syncFailed);
      expect(failedTx.syncError, isNotNull);
    });

    test('User action retry and void update transaction status accordingly', () async {
      final now = DateTime.now();
      const txId = 'tx_user_action_004';

      final localTx = SaleTransaction(
        id: txId,
        shopId: testShopId,
        type: 'sale',
        items: const [],
        subtotal: 50.0,
        discount: 0.0,
        taxAmount: 0.0,
        total: 50.0,
        paymentMethod: 'cash',
        status: TransactionStatus.conflict,
        syncError: 'Insufficient stock',
        createdBy: 'user_1',
        createdByName: 'Alice',
        createdAt: now,
      );
      await localDb.putTransaction(testShopId, localTx);

      final queueItem = SyncQueueItem(
        localId: txId,
        shopId: testShopId,
        userId: 'user_1',
        operationType: SyncOperationType.createSale,
        entityType: 'sale',
        entityId: txId,
        payload: {'items': []},
        status: SyncStatus.conflict,
        conflictCategory: SyncConflictCategory.stockConflict,
        conflictExplanation: 'Insufficient stock',
        createdAt: now,
        updatedAt: now,
      );
      await localDb.syncQueueBox.put(txId, queueItem);

      // Test Retry
      connectivity.setOnline(false); // don't auto-run
      await processor.retryOperation(txId);

      final retriedTx = localDb.getTransaction(testShopId, txId);
      expect(retriedTx?.status, TransactionStatus.syncPending);
      expect(retriedTx?.syncError, isNull);
      expect(localDb.syncQueueBox.get(txId)?.status, SyncStatus.pending);

      // Test Void
      await processor.voidOperation(txId);
      final voidedTx = localDb.getTransaction(testShopId, txId);
      expect(voidedTx?.status, TransactionStatus.voided);
      expect(localDb.syncQueueBox.containsKey(txId), isFalse);
    });
  });
}
