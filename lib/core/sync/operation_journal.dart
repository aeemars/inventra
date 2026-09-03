import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import '../cache/local_database.dart';
import '../../shared/models/stock_movement.dart';
import 'sync_models.dart';
import 'sync_processor.dart';

/// Staged status of an offline multi-step operation for crash-resilience.
enum LocalOperationStatus {
  preparing,
  committing,
  committed,
  rolledBack,
}

/// Durable local journal entry tracking multi-step mutations.
class OperationJournalEntry extends Equatable {
  final String operationId;
  final String shopId;
  final String operationType; // sale, restock, stockAdjustment, createProduct, updateProduct, deleteProduct
  final LocalOperationStatus status;
  final DateTime createdAt;
  final Map<String, dynamic> backupState;
  final Map<String, dynamic> targetMutations;

  const OperationJournalEntry({
    required this.operationId,
    required this.shopId,
    required this.operationType,
    required this.status,
    required this.createdAt,
    required this.backupState,
    required this.targetMutations,
  });

  OperationJournalEntry copyWith({
    String? operationId,
    String? shopId,
    String? operationType,
    LocalOperationStatus? status,
    DateTime? createdAt,
    Map<String, dynamic>? backupState,
    Map<String, dynamic>? targetMutations,
  }) {
    return OperationJournalEntry(
      operationId: operationId ?? this.operationId,
      shopId: shopId ?? this.shopId,
      operationType: operationType ?? this.operationType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      backupState: backupState ?? this.backupState,
      targetMutations: targetMutations ?? this.targetMutations,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'operationId': operationId,
      'shopId': shopId,
      'operationType': operationType,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'backupState': backupState,
      'targetMutations': targetMutations,
    };
  }

  factory OperationJournalEntry.fromMap(Map<dynamic, dynamic> map) {
    return OperationJournalEntry(
      operationId: map['operationId'] as String,
      shopId: map['shopId'] as String? ?? '',
      operationType: map['operationType'] as String? ?? 'unknown',
      status: LocalOperationStatus.values.firstWhere(
        (e) => e.name == (map['status'] as String?),
        orElse: () => LocalOperationStatus.preparing,
      ),
      createdAt: DateTime.parse(map['createdAt'] as String),
      backupState: Map<String, dynamic>.from(map['backupState'] as Map? ?? {}),
      targetMutations:
          Map<String, dynamic>.from(map['targetMutations'] as Map? ?? {}),
    );
  }

  @override
  List<Object?> get props => [
        operationId,
        shopId,
        operationType,
        status,
        createdAt,
      ];
}

/// Hive adapter for OperationJournalEntry (TypeId: 11)
class OperationJournalEntryAdapter extends TypeAdapter<OperationJournalEntry> {
  @override
  final int typeId = 11;

  @override
  OperationJournalEntry read(BinaryReader reader) {
    final map = reader.readMap();
    return OperationJournalEntry.fromMap(map);
  }

  @override
  void write(BinaryWriter writer, OperationJournalEntry obj) {
    writer.writeMap(obj.toMap());
  }
}

/// Centralized manager for executing atomic local mutations with crash-safety.
class OfflineOperationManager {
  static const String boxName = 'local_operations';

  /// Execute an atomic offline sale:
  /// Staged journal -> stock deduction -> movements -> transaction (completed_local) -> sync queue item.
  static Future<String> executeAtomicSale({
    required String shopId,
    required String operationId,
    required String userId,
    required String userName,
    required List<Map<String, dynamic>> items,
    required String paymentMethod,
    double discount = 0,
    String? note,
    required LocalDatabase localDb,
    SyncProcessor? syncProcessor,
  }) async {
    final now = DateTime.now();

    // 1. Snapshot backup state of products
    final backupProducts = <String, dynamic>{};
    for (final it in items) {
      final pId = it['productId'] as String;
      final product = localDb.getProduct(shopId, pId);
      if (product != null) {
        backupProducts[pId] = {'quantity': product.quantity};
      }
    }

    // 2. Prepare target mutations
    double subtotal = 0;
    final saleItems = <SaleItem>[];
    final productUpdates = <String, int>{}; // pId -> newQty
    final stockMovements = <StockMovement>[];

    for (final it in items) {
      final pId = it['productId'] as String;
      final qty = (it['quantity'] as num).toInt();
      final product = localDb.getProduct(shopId, pId)!;
      final unitPrice =
          (it['unitPrice'] as num?)?.toDouble() ?? product.sellingPrice;
      final lineTotal = unitPrice * qty;
      subtotal += lineTotal;

      final newQty = product.quantity - qty;
      productUpdates[pId] = newQty;

      final movementId = 'sm_${operationId}_$pId';
      stockMovements.add(StockMovement(
        id: movementId,
        productId: pId,
        productName: product.name,
        type: 'sale',
        quantityChange: -qty,
        quantityBefore: product.quantity,
        quantityAfter: newQty,
        reference: operationId,
        userId: userId,
        userName: userName,
        source: 'pos',
        createdAt: now,
        shopId: shopId,
      ));

      saleItems.add(SaleItem(
        productId: pId,
        productName: product.name,
        sku: product.sku,
        quantity: qty,
        unitPrice: unitPrice,
        totalPrice: lineTotal,
      ));
    }

    final total = subtotal - discount;

    final transaction = SaleTransaction(
      id: operationId,
      type: 'sale',
      items: saleItems,
      subtotal: subtotal,
      discount: discount,
      taxAmount: 0,
      total: total,
      paymentMethod: paymentMethod,
      status: TransactionStatus.completedLocal,
      note: note,
      createdBy: userId,
      createdByName: userName,
      createdAt: now,
      shopId: shopId,
      operationId: operationId,
    );

    final syncItem = SyncQueueItem(
      localId: operationId,
      shopId: shopId,
      userId: userId,
      operationType: SyncOperationType.createSale,
      entityType: 'sale',
      entityId: operationId,
      payload: {
        'items': items,
        'paymentMethod': paymentMethod,
        'discount': discount,
        'note': note,
      },
      createdAt: now,
      updatedAt: now,
    );

    // 3. Stage Journal Entry (preparing)
    final journalKey = LocalDatabase.scopedKey(shopId, operationId);
    var entry = OperationJournalEntry(
      operationId: operationId,
      shopId: shopId,
      operationType: 'sale',
      status: LocalOperationStatus.preparing,
      createdAt: now,
      backupState: {'products': backupProducts},
      targetMutations: {
        'productUpdates': productUpdates,
        'transactionId': operationId,
      },
    );
    await localDb.localOperationsBox.put(journalKey, entry);

    // 4. Mark Committing
    entry = entry.copyWith(status: LocalOperationStatus.committing);
    await localDb.localOperationsBox.put(journalKey, entry);

    // 5. Apply Local Mutations Atomically
    for (final entry in productUpdates.entries) {
      final p = localDb.getProduct(shopId, entry.key);
      if (p != null) {
        await localDb.putProduct(
            shopId, p.copyWith(quantity: entry.value, updatedAt: now));
      }
    }

    for (final m in stockMovements) {
      await localDb.putStockMovement(shopId, m);
    }

    await localDb.putTransaction(shopId, transaction);

    // 6. Persist Sync Queue Entry
    if (syncProcessor != null) {
      await syncProcessor.enqueue(syncItem);
    } else {
      await localDb.syncQueueBox.put(syncItem.localId, syncItem);
    }

    // 7. Mark Committed
    entry = entry.copyWith(status: LocalOperationStatus.committed);
    await localDb.localOperationsBox.put(journalKey, entry);

    return operationId;
  }

  /// Scan and recover incomplete journal operations on startup.
  static Future<int> recoverIncompleteOperations({
    required LocalDatabase localDb,
    SyncProcessor? syncProcessor,
  }) async {
    if (!localDb.isInitialized) return 0;

    int recoveredCount = 0;
    final entries = localDb.localOperationsBox.values.toList();

    for (final entry in entries) {
      final scopedKey = LocalDatabase.scopedKey(entry.shopId, entry.operationId);

      if (entry.status == LocalOperationStatus.preparing) {
        debugPrint(
            '🔄 [JOURNAL RECOVERY] Rolling back interrupted preparing operation: ${entry.operationId}');
        // Rollback any partial mutations using backup state
        final backupProds =
            entry.backupState['products'] as Map<dynamic, dynamic>? ?? {};
        for (final item in backupProds.entries) {
          final pId = item.key as String;
          final originalQty =
              ((item.value as Map)['quantity'] as num?)?.toInt();
          if (originalQty != null) {
            final p = localDb.getProduct(entry.shopId, pId);
            if (p != null) {
              await localDb.putProduct(
                  entry.shopId, p.copyWith(quantity: originalQty));
            }
          }
        }

        // Mark rolled back
        await localDb.localOperationsBox.put(
          scopedKey,
          entry.copyWith(status: LocalOperationStatus.rolledBack),
        );
        recoveredCount++;
      } else if (entry.status == LocalOperationStatus.committing) {
        debugPrint(
            '🔄 [JOURNAL RECOVERY] Finalizing interrupted committing operation: ${entry.operationId}');
        // Verify queue item exists; if missing, rebuild it
        final queueExists = localDb.syncQueueBox.containsKey(entry.operationId);
        if (!queueExists) {
          if (entry.operationType == 'sale') {
            final tx = localDb.getTransaction(entry.shopId, entry.operationId);
            if (tx != null) {
              final syncItem = SyncQueueItem(
                localId: entry.operationId,
                shopId: entry.shopId,
                userId: tx.createdBy,
                operationType: SyncOperationType.createSale,
                entityType: 'sale',
                entityId: entry.operationId,
                payload: {
                  'items': tx.items
                      .map((i) => {
                            'productId': i.productId,
                            'quantity': i.quantity,
                            'unitPrice': i.unitPrice,
                          })
                      .toList(),
                  'paymentMethod': tx.paymentMethod,
                  'discount': tx.discount,
                  'note': tx.note,
                },
                createdAt: tx.createdAt,
                updatedAt: DateTime.now(),
              );

              if (syncProcessor != null) {
                await syncProcessor.enqueue(syncItem);
              } else {
                await localDb.syncQueueBox.put(syncItem.localId, syncItem);
              }
            }
          }
        }

        // Mark committed
        await localDb.localOperationsBox.put(
          scopedKey,
          entry.copyWith(status: LocalOperationStatus.committed),
        );
        recoveredCount++;
      }
    }

    if (recoveredCount > 0) {
      debugPrint(
          '🏁 [JOURNAL RECOVERY] Successfully resolved $recoveredCount incomplete operations.');
    }
    return recoveredCount;
  }
}
