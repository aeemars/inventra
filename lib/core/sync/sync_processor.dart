import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import '../cache/local_database.dart';
import '../connectivity/connectivity_service.dart';
import '../constants/firestore_paths.dart';
import '../../features/inventory/data/models/product_model.dart';
import '../../features/sales/data/models/transaction_model.dart';
import '../../shared/models/stock_movement_model.dart';
import 'sync_models.dart';

/// The core background synchronization engine for Inventra.
/// Implements deterministic topological dependency resolution, bounded exponential backoff,
/// structured conflict classification, stale processing recovery, and tenant-safe multi-shop execution.
class SyncProcessor with WidgetsBindingObserver {
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

  final _stateController = StreamController<SyncEngineState>.broadcast();
  SyncEngineState _currentState = SyncEngineState.idle;
  SyncEngineState get currentState => _currentState;
  Stream<SyncEngineState> get onStateChanged => _stateController.stream;

  StreamSubscription? _connectivitySub;
  String? _activeShopId;
  String? get activeShopId => _activeShopId;

  SyncProcessor({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    LocalDatabase? localDb,
    ConnectivityService? connectivity,
    String? initialShopId,
  })  : _firestore = firestore,
        _functions = functions,
        _localDb = localDb ?? LocalDatabase.instance,
        _connectivity = connectivity ?? ConnectivityService(),
        _activeShopId = initialShopId;

  void initialize() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // In unit test environment WidgetsBinding may not be attached
    }

    // Recover any stale processing operations from prior crashed sessions
    recoverStaleProcessingItems();

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [SYNC LIFECYCLE] App resumed — checking connectivity and queue.');
      if (_connectivity.isOnline) {
        processQueue();
      }
    }
  }

  void setActiveShop(String? shopId) {
    if (_activeShopId != shopId) {
      _activeShopId = shopId;
      debugPrint('🏪 [SYNC TENANT] Active shop set to: $shopId');
    }
  }

  void _setState(SyncEngineState newState) {
    if (_currentState != newState && !_stateController.isClosed) {
      _currentState = newState;
      _stateController.add(_currentState);
    }
  }

  /// Stale Processing Recovery (Part 5.1):
  /// Detects operations stranded in "processing" state from an app crash / force-quit,
  /// and resets them to "pending" so the queue never blocks.
  int recoverStaleProcessingItems({Duration threshold = const Duration(seconds: 60)}) {
    if (!_localDb.isInitialized) return 0;
    final queueBox = _localDb.syncQueueBox;
    final now = DateTime.now();
    int recoveredCount = 0;

    for (final item in queueBox.values) {
      if (item.status == SyncStatus.processing) {
        final isStale = item.processingStartedAt == null ||
            now.difference(item.processingStartedAt!) > threshold;
        if (isStale) {
          queueBox.put(
            item.localId,
            item.copyWith(
              status: SyncStatus.pending,
              clearProcessingStartedAt: true,
              updatedAt: now,
            ),
          );
          recoveredCount++;
          debugPrint('🔧 [SYNC RECOVERY] Reset stale processing operation: ${item.localId}');
        }
      }
    }
    return recoveredCount;
  }

  /// Adds a new mutation to the persistent sync queue and attempts sync if online.
  Future<void> enqueue(SyncQueueItem item) async {
    await _localDb.syncQueueBox.put(item.localId, item);
    debugPrint('📥 [SYNC ENQUEUE] ${item.operationType} (${item.localId}) for shop ${item.shopId}');
    if (_connectivity.isOnline) {
      unawaited(processQueue());
    }
  }

  /// Detects circular dependency cycles in candidate items.
  Set<String> _detectCycles(List<SyncQueueItem> items) {
    final itemMap = {for (final item in items) item.localId: item};
    final visited = <String, int>{}; // 0: unvisited, 1: visiting, 2: visited
    final inCycle = <String>{};
    final path = <String>[];

    void dfs(String id) {
      visited[id] = 1;
      path.add(id);

      final item = itemMap[id];
      if (item != null) {
        for (final depId in item.allDependencies) {
          if (itemMap.containsKey(depId)) {
            final state = visited[depId] ?? 0;
            if (state == 1) {
              final cycleStartIdx = path.indexOf(depId);
              if (cycleStartIdx != -1) {
                inCycle.addAll(path.sublist(cycleStartIdx));
              }
            } else if (state == 0) {
              dfs(depId);
            }
          }
        }
      }

      path.removeLast();
      visited[id] = 2;
    }

    for (final id in itemMap.keys) {
      if ((visited[id] ?? 0) == 0) {
        dfs(id);
      }
    }

    return inCycle;
  }

  /// Primary 13-step synchronization engine.
  Future<void> processQueue() async {
    // 1. Mutex & Connectivity checks
    if (_isProcessing) return;
    if (_connectivity.isOffline) {
      _setState(SyncEngineState.offline);
      return;
    }

    _isProcessing = true;
    _setState(SyncEngineState.syncing);

    try {
      final queueBox = _localDb.syncQueueBox;
      final targetShopId = _activeShopId;

      // 2. Recover any stale processing operations
      recoverStaleProcessingItems();

      // 3. Load all pending/processing items for active shop
      final allItems = queueBox.values
          .where((i) =>
              targetShopId == null || i.shopId == targetShopId)
          .toList();

      // 4. Circular dependency detection
      final cycles = _detectCycles(allItems.where((i) => i.status == SyncStatus.pending || i.status == SyncStatus.processing).toList());
      if (cycles.isNotEmpty) {
        for (final cycleId in cycles) {
          final item = queueBox.get(cycleId);
          if (item != null) {
            await queueBox.put(
              cycleId,
              item.copyWith(
                status: SyncStatus.conflict,
                conflictCategory: SyncConflictCategory.dependencyConflict,
                conflictExplanation: 'Circular synchronization dependency detected',
                updatedAt: DateTime.now(),
              ),
            );
            debugPrint('⚠️ [SYNC CYCLE] Circular dependency marked conflict: $cycleId');
          }
        }
      }

      // 5. Dependency failure propagation: if prerequisite is conflict, cascade conflict
      for (final item in queueBox.values) {
        if (item.status == SyncStatus.pending || item.status == SyncStatus.processing) {
          for (final depId in item.allDependencies) {
            final depItem = queueBox.get(depId);
            if (depItem != null && depItem.status == SyncStatus.conflict) {
              await queueBox.put(
                item.localId,
                item.copyWith(
                  status: SyncStatus.conflict,
                  conflictCategory: SyncConflictCategory.dependencyConflict,
                  conflictExplanation:
                      'Prerequisite operation ($depId) resulted in a conflict.',
                  updatedAt: DateTime.now(),
                ),
              );
              break;
            }
          }
        }
      }

      bool hasConflict = false;
      bool hasError = false;
      int processedCount = 0;

      // 6. Deterministic Topological Processing Loop
      while (true) {
        if (_connectivity.isOffline) {
          _setState(SyncEngineState.offline);
          break;
        }

        final currentPending = queueBox.values
            .where((i) =>
                (targetShopId == null || i.shopId == targetShopId) &&
                (i.status == SyncStatus.pending || i.status == SyncStatus.processing))
            .toList();

        if (currentPending.isEmpty) break;

        // An operation is ready when ALL of its dependencies are satisfied
        // (i.e. not present in the unfulfilled pending/failed/conflict queue).
        final unfulfilledIds = currentPending.map((i) => i.localId).toSet();

        final readyItems = currentPending.where((item) {
          for (final depId in item.allDependencies) {
            if (unfulfilledIds.contains(depId)) {
              return false; // Prerequisite has not yet executed
            }
          }
          return true;
        }).toList();

        if (readyItems.isEmpty) {
          // Unresolved dependencies remain (e.g. waiting on a blocked item)
          debugPrint('⏳ [SYNC WAITING] Dependencies pending, cannot proceed further in this pass.');
          _setState(SyncEngineState.waitingDependency);
          break;
        }

        // Pick the oldest ready item (FIFO among ready tasks)
        readyItems.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final itemToExecute = readyItems.first;

        // Tenant check: verify shop context
        if (targetShopId != null && itemToExecute.shopId != targetShopId) {
          debugPrint('🛡️ [SYNC TENANT GUARD] Skipping item from different shop: ${itemToExecute.shopId}');
          continue;
        }

        final now = DateTime.now();
        await queueBox.put(
          itemToExecute.localId,
          itemToExecute.copyWith(
            status: SyncStatus.processing,
            processingStartedAt: now,
            updatedAt: now,
          ),
        );

        debugPrint('🚀 [SYNC START] operation=${itemToExecute.operationType} id=${itemToExecute.localId} deps=${itemToExecute.allDependencies}');

        try {
          await _executeOperation(itemToExecute);
          // Success: delete from pending queue
          await queueBox.delete(itemToExecute.localId);
          processedCount++;
          debugPrint('✅ [SYNC SUCCESS] operation=${itemToExecute.operationType} id=${itemToExecute.localId}');
        } catch (e) {
          debugPrint('❌ [SYNC ERROR] operation=${itemToExecute.operationType} id=${itemToExecute.localId} error=$e');

          final conflictCat = _classifyError(e);

          if (conflictCat != null) {
            hasConflict = true;
            final explanation = _extractExplanation(e, conflictCat);

            await queueBox.put(
              itemToExecute.localId,
              itemToExecute.copyWith(
                status: SyncStatus.conflict,
                conflictCategory: conflictCat,
                conflictExplanation: explanation,
                lastError: e.toString(),
                updatedAt: DateTime.now(),
              ),
            );

            // If sale suffered a stock conflict, update the local transaction record
            if (itemToExecute.operationType == SyncOperationType.createSale &&
                itemToExecute.entityId != null) {
              final tx = _localDb.salesTransactionsBox.get(itemToExecute.entityId!);
              if (tx != null) {
                await _localDb.salesTransactionsBox.put(
                  itemToExecute.entityId!,
                  tx.copyWith(status: 'conflict', note: explanation),
                );
              }
            }

            debugPrint('⚠️ [SYNC CONFLICT] Classified as ${conflictCat.name}: $explanation');
          } else {
            // Transient error (network loss, timeout)
            hasError = true;
            final newRetryCount = itemToExecute.retryCount + 1;
            const maxRetries = 5;

            if (newRetryCount >= maxRetries) {
              await queueBox.put(
                itemToExecute.localId,
                itemToExecute.copyWith(
                  status: SyncStatus.failed,
                  retryCount: newRetryCount,
                  lastError: e.toString(),
                  updatedAt: DateTime.now(),
                ),
              );
              debugPrint('🛑 [SYNC FAILED] Max retries reached ($maxRetries) for ${itemToExecute.localId}');
            } else {
              final backoffMs = min(pow(2, newRetryCount) * 500, 30000).toInt();
              await queueBox.put(
                itemToExecute.localId,
                itemToExecute.copyWith(
                  status: SyncStatus.pending,
                  retryCount: newRetryCount,
                  lastError: e.toString(),
                  updatedAt: DateTime.now(),
                ),
              );
              debugPrint('🔁 [SYNC RETRY] Retry #$newRetryCount scheduled with backoff ${backoffMs}ms for ${itemToExecute.localId}');
              _setState(SyncEngineState.retryWait);
            }
            break; // Stop loop on transient failure to prevent hammering
          }
        }
      }

      // 7. Remote reconciliation (Pull changes systematically without overwriting local pending items)
      if (targetShopId != null && _connectivity.isOnline) {
        await pullRemoteChanges(targetShopId);
      }

      // 8. Update terminal state
      if (hasConflict) {
        _setState(SyncEngineState.conflict);
      } else if (hasError) {
        _setState(SyncEngineState.error);
      } else {
        _setState(SyncEngineState.idle);
      }

      debugPrint('🏁 [SYNC COMPLETE] Processed: $processedCount, Conflicts: $hasConflict, Errors: $hasError');
    } catch (e) {
      debugPrint('💥 [SYNC FATAL] Unexpected error in sync processor: $e');
      _setState(SyncEngineState.error);
    } finally {
      _isProcessing = false;
    }
  }

  /// Classifies caught exceptions into structured business conflict categories.
  SyncConflictCategory? _classifyError(dynamic error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'failed-precondition':
          final msg = (error.message ?? '').toLowerCase();
          if (msg.contains('stock') || msg.contains('available') || msg.contains('quantity')) {
            return SyncConflictCategory.stockConflict;
          }
          if (msg.contains('active') || msg.contains('not found')) {
            return SyncConflictCategory.deletedResource;
          }
          return SyncConflictCategory.validationConflict;
        case 'permission-denied':
          return SyncConflictCategory.permissionConflict;
        case 'not-found':
          return SyncConflictCategory.deletedResource;
        case 'invalid-argument':
          return SyncConflictCategory.validationConflict;
        case 'already-exists':
          return SyncConflictCategory.duplicateOperation;
        default:
          return null;
      }
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return SyncConflictCategory.permissionConflict;
        case 'not-found':
          return SyncConflictCategory.deletedResource;
        case 'failed-precondition':
          return SyncConflictCategory.validationConflict;
        default:
          return null;
      }
    }

    final errStr = error.toString().toLowerCase();
    if (errStr.contains('insufficient stock') || errStr.contains('failed-precondition')) {
      return SyncConflictCategory.stockConflict;
    }
    if (errStr.contains('permission-denied') || errStr.contains('permission denied')) {
      return SyncConflictCategory.permissionConflict;
    }
    if (errStr.contains('not-found') || errStr.contains('not found')) {
      return SyncConflictCategory.deletedResource;
    }
    return null;
  }

  String _extractExplanation(dynamic error, SyncConflictCategory category) {
    if (error is FirebaseFunctionsException && error.message != null) {
      return error.message!;
    }
    switch (category) {
      case SyncConflictCategory.stockConflict:
        return 'Server stock was insufficient to fulfill one or more items in this transaction.';
      case SyncConflictCategory.permissionConflict:
        return 'Your permissions have changed. You no longer have authorization for this operation.';
      case SyncConflictCategory.deletedResource:
        return 'The referenced product or resource was deleted or deactivated on the server.';
      case SyncConflictCategory.validationConflict:
        return 'The operation failed server business validation rules.';
      case SyncConflictCategory.dependencyConflict:
        return 'A required prerequisite operation failed or conflicted.';
      case SyncConflictCategory.duplicateOperation:
        return 'This operation was already processed on the server.';
      case SyncConflictCategory.productConflict:
        return 'A concurrent edit conflict occurred on the server.';
      case SyncConflictCategory.unknownConflict:
        return error.toString();
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
        await docRef.update({
          'isActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        break;

      case SyncOperationType.createSale:
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
        } catch (_) {}
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
            await _localDb.salesTransactionsBox.put(
              item.entityId!,
              tx.copyWith(status: 'completed'),
            );
          }
        }
        break;

      case SyncOperationType.restock:
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
        } catch (_) {}
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
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
        } catch (_) {}
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

  /// Two-way systematic remote reconciliation (Part 15):
  /// Pulls remote Firestore changes into Hive cache while protecting any
  /// local entity that has an unsynchronized mutation in the queue.
  Future<void> pullRemoteChanges(String shopId) async {
    if (_connectivity.isOffline) return;

    try {
      // 1. Gather all entity IDs with pending/conflict operations
      final pendingEntityIds = _localDb.syncQueueBox.values
          .where((i) =>
              i.shopId == shopId &&
              i.entityId != null &&
              (i.status == SyncStatus.pending ||
                  i.status == SyncStatus.processing ||
                  i.status == SyncStatus.conflict))
          .map((i) => i.entityId!)
          .toSet();

      // 2. Fetch remote products and reconcile
      final productSnap =
          await _firestoreInstance.collection(FirestorePaths.products(shopId)).get();

      for (final doc in productSnap.docs) {
        if (!pendingEntityIds.contains(doc.id)) {
          final product = ProductModel.fromFirestore(doc).toEntity();
          await _localDb.productsBox.put(doc.id, product);
        }
      }

      // 3. Fetch remote stock movements
      final movementSnap = await _firestoreInstance
          .collection(FirestorePaths.stockMovements(shopId))
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      for (final doc in movementSnap.docs) {
        final movement = StockMovementModel.fromFirestore(doc).toEntity();
        await _localDb.stockMovementsBox.put(doc.id, movement);
      }

      // 4. Fetch remote transactions
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
      debugPrint('⚠️ [SYNC RECONCILE] pullRemoteChanges error: $e');
    }
  }

  /// User action: Retries an operation from the Conflict or Failed state.
  Future<void> retryOperation(String localId) async {
    final item = _localDb.syncQueueBox.get(localId);
    if (item == null) return;

    await _localDb.syncQueueBox.put(
      localId,
      item.copyWith(
        status: SyncStatus.pending,
        retryCount: 0,
        lastError: null,
        conflictCategory: null,
        conflictExplanation: null,
        updatedAt: DateTime.now(),
      ),
    );
    debugPrint('🔄 [SYNC USER ACTION] Retrying operation: $localId');
    if (_connectivity.isOnline) {
      unawaited(processQueue());
    }
  }

  /// User action: Voids a conflicted sale and removes it from the sync queue.
  Future<void> voidOperation(String localId) async {
    final item = _localDb.syncQueueBox.get(localId);
    if (item == null) return;

    if (item.operationType == SyncOperationType.createSale && item.entityId != null) {
      final tx = _localDb.salesTransactionsBox.get(item.entityId!);
      if (tx != null) {
        await _localDb.salesTransactionsBox.put(
          item.entityId!,
          tx.copyWith(status: 'voided'),
        );
      }
    }

    await _localDb.syncQueueBox.delete(localId);
    debugPrint('🗑️ [SYNC USER ACTION] Voided and discarded operation: $localId');
    _setState(SyncEngineState.idle);
  }

  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _connectivitySub?.cancel();
    _stateController.close();
  }
}
