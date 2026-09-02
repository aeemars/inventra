import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../cache/local_database.dart';
import '../connectivity/connectivity_service.dart';
import '../constants/firestore_paths.dart';
import '../../features/inventory/data/models/product_model.dart';
import '../../features/sales/data/models/transaction_model.dart';
import '../../shared/models/stock_movement_model.dart';
import 'sync_models.dart';

enum SyncEngineState {
  idle,
  syncing,
  offline,
  error,
}

/// The core background synchronization engine for Inventra.
class SyncProcessor {
  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  final LocalDatabase _localDb;
  final ConnectivityService _connectivity;

  FirebaseFirestore get _firestoreInstance =>
      _firestore ?? FirebaseFirestore.instance;
  FirebaseFunctions get _functionsInstance =>
      _functions ?? FirebaseFunctions.instance;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  final _stateController =
      StreamController<SyncEngineState>.broadcast();
  SyncEngineState _currentState = SyncEngineState.idle;
  SyncEngineState get currentState => _currentState;
  Stream<SyncEngineState> get onStateChanged => _stateController.stream;

  StreamSubscription? _connectivitySub;

  SyncProcessor({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    LocalDatabase? localDb,
    ConnectivityService? connectivity,
  })  : _firestore = firestore,
        _functions = functions,
        _localDb = localDb ?? LocalDatabase.instance,
        _connectivity = connectivity ?? ConnectivityService();

  void initialize() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        processQueue();
      } else {
        _setState(SyncEngineState.offline);
      }
    });

    if (_connectivity.isOnline) {
      processQueue();
    } else {
      _setState(SyncEngineState.offline);
    }
  }

  void _setState(SyncEngineState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      _stateController.add(_currentState);
    }
  }

  /// Adds a new mutation to the persistent sync queue and attempts sync if online.
  Future<void> enqueue(SyncQueueItem item) async {
    await _localDb.syncQueueBox.put(item.localId, item);
    if (_connectivity.isOnline) {
      unawaited(processQueue());
    }
  }

  /// Processes all pending items in the queue sequentially.
  Future<void> processQueue() async {
    if (_isProcessing) return;
    if (_connectivity.isOffline) {
      _setState(SyncEngineState.offline);
      return;
    }

    _isProcessing = true;
    _setState(SyncEngineState.syncing);

    try {
      final queueBox = _localDb.syncQueueBox;
      final pendingItems = queueBox.values
          .where((i) => i.status == SyncStatus.pending || i.status == SyncStatus.processing)
          .toList();

      if (pendingItems.isEmpty) {
        _setState(SyncEngineState.idle);
        _isProcessing = false;
        return;
      }

      // Sort items: dependencies first, then FIFO by createdAt
      pendingItems.sort((a, b) {
        if (a.dependsOnOperationId != null && a.dependsOnOperationId == b.localId) {
          return 1;
        }
        if (b.dependsOnOperationId != null && b.dependsOnOperationId == a.localId) {
          return -1;
        }
        return a.createdAt.compareTo(b.createdAt);
      });

      bool hasFailure = false;

      for (final item in pendingItems) {
        // Double-check connectivity between items
        if (_connectivity.isOffline) {
          _setState(SyncEngineState.offline);
          break;
        }

        try {
          await queueBox.put(item.localId, item.copyWith(status: SyncStatus.processing));
          await _executeOperation(item);
          // Mark synced and remove from pending queue
          await queueBox.delete(item.localId);
          debugPrint('✅ Synced operation: ${item.operationType} (${item.localId})');
        } catch (e) {
          debugPrint('❌ Sync error on ${item.operationType} (${item.localId}): $e');
          final isConflict = e.toString().contains('failed-precondition') ||
              e.toString().contains('not-found') ||
              e.toString().contains('permission-denied');

          if (isConflict) {
            await queueBox.put(
              item.localId,
              item.copyWith(
                status: SyncStatus.conflict,
                lastError: e.toString(),
                updatedAt: DateTime.now(),
              ),
            );
            hasFailure = true;
          } else {
            // Transient failure (network/timeout) -> increment retry count and stop batch
            await queueBox.put(
              item.localId,
              item.copyWith(
                status: SyncStatus.pending,
                retryCount: item.retryCount + 1,
                lastError: e.toString(),
                updatedAt: DateTime.now(),
              ),
            );
            hasFailure = true;
            break; // Stop and retry on next trigger
          }
        }
      }

      _setState(hasFailure ? SyncEngineState.error : SyncEngineState.idle);
    } catch (e) {
      debugPrint('⚠️ Sync queue processing failed: $e');
      _setState(SyncEngineState.error);
    } finally {
      _isProcessing = false;
    }
  }

  /// Executes an individual queued operation.
  Future<void> _executeOperation(SyncQueueItem item) async {
    switch (item.operationType) {
      case SyncOperationType.createProduct:
        final docRef = _firestoreInstance
            .collection(FirestorePaths.products(item.shopId))
            .doc(item.entityId);
        await docRef.set(item.payload, SetOptions(merge: true));
        break;

      case SyncOperationType.updateProduct:
        final docRef = _firestoreInstance
            .collection(FirestorePaths.products(item.shopId))
            .doc(item.entityId);
        await docRef.update(item.payload);
        break;

      case SyncOperationType.deleteProduct:
        final docRef = _firestoreInstance
            .collection(FirestorePaths.products(item.shopId))
            .doc(item.entityId);
        // Soft delete/deactivate to preserve historical transaction integrity
        await docRef.update({
          'isActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        break;

      case SyncOperationType.createSale:
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        final callable = _functionsInstance.httpsCallable('validateStockDeduction');
        final response = await callable.call({
          'shopId': item.shopId,
          'items': item.payload['items'],
          'paymentMethod': item.payload['paymentMethod'] ?? 'cash',
          'discount': item.payload['discount'] ?? 0,
          'note': item.payload['note'],
          'operationId': item.localId,
        });
        final resData = Map<String, dynamic>.from(response.data as Map);
        final serverTxId = resData['transactionId'] as String?;
        if (serverTxId != null && item.entityId != null) {
          final tx = _localDb.salesTransactionsBox.get(item.entityId);
          if (tx != null) {
            // Update local transaction record status to synced
            await _localDb.salesTransactionsBox.put(
              item.entityId!,
              tx.copyWith(status: 'completed'),
            );
          }
        }
        break;

      case SyncOperationType.restock:
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        final callable = _functionsInstance.httpsCallable('processRestock');
        await callable.call({
          'shopId': item.shopId,
          'productId': item.entityId,
          'quantity': item.payload['quantity'],
          'costPrice': item.payload['costPrice'],
          'supplier': item.payload['supplier'],
          'note': item.payload['note'],
          'operationId': item.localId,
        });
        break;

      case SyncOperationType.stockAdjustment:
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        final callable = _functionsInstance.httpsCallable('processStockAdjustment');
        await callable.call({
          'shopId': item.shopId,
          'productId': item.entityId,
          'quantityChange': item.payload['quantityChange'],
          'newQuantity': item.payload['newQuantity'],
          'reason': item.payload['reason'],
          'operationId': item.localId,
        });
        break;

      case SyncOperationType.createScan:
        final docRef = _firestoreInstance
            .collection(FirestorePaths.scanHistory(item.shopId))
            .doc(item.entityId);
        await docRef.set(item.payload, SetOptions(merge: true));
        break;

      case SyncOperationType.createCategory:
        final docRef = _firestoreInstance
            .collection(FirestorePaths.categories(item.shopId))
            .doc(item.entityId);
        await docRef.set(item.payload, SetOptions(merge: true));
        break;

      case SyncOperationType.updateCategory:
        final docRef = _firestoreInstance
            .collection(FirestorePaths.categories(item.shopId))
            .doc(item.entityId);
        await docRef.update(item.payload);
        break;

      case SyncOperationType.deleteCategory:
        final docRef = _firestoreInstance
            .collection(FirestorePaths.categories(item.shopId))
            .doc(item.entityId);
        await docRef.delete();
        break;
    }
  }

  /// Two-way reconciliation: Pull remote changes into Hive cache
  /// while preserving local records that have pending operations.
  Future<void> pullRemoteChanges(String shopId) async {
    if (_connectivity.isOffline) return;

    try {
      // 1. Fetch remote products
      final productSnap =
          await _firestoreInstance.collection(FirestorePaths.products(shopId)).get();
      final pendingProductOps = _localDb.syncQueueBox.values
          .where((i) => i.shopId == shopId && i.entityType == 'product')
          .map((i) => i.entityId)
          .toSet();

      for (final doc in productSnap.docs) {
        if (!pendingProductOps.contains(doc.id)) {
          final product = ProductModel.fromFirestore(doc).toEntity();
          await _localDb.productsBox.put(doc.id, product);
        }
      }

      // 2. Fetch remote stock movements
      final movementSnap = await _firestoreInstance
          .collection(FirestorePaths.stockMovements(shopId))
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      for (final doc in movementSnap.docs) {
        final movement = StockMovementModel.fromFirestore(doc).toEntity();
        await _localDb.stockMovementsBox.put(doc.id, movement);
      }

      // 3. Fetch remote transactions
      final txSnap = await _firestoreInstance
          .collection(FirestorePaths.transactions(shopId))
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      for (final doc in txSnap.docs) {
        final tx = TransactionModel.fromFirestore(doc).toEntity();
        await _localDb.salesTransactionsBox.put(doc.id, tx);
      }
    } catch (e) {
      debugPrint('⚠️ pullRemoteChanges error: $e');
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _stateController.close();
  }
}
