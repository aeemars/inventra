import 'package:equatable/equatable.dart';

/// Standard lifecycle status values for transactions
abstract class TransactionStatus {
  static const String draft = 'draft';
  static const String completedLocal = 'completed_local';
  static const String syncPending = 'sync_pending';
  static const String syncing = 'syncing';
  static const String synced = 'synced';
  static const String syncFailed = 'sync_failed';
  static const String conflict = 'conflict';
  static const String voided = 'voided';
}

/// Represents a stock movement (sale, restock, adjustment)
class StockMovement extends Equatable {
  final String id;
  final String productId;
  final String productName;
  final String type; // sale, restock, adjustment, return
  final int quantityChange;
  final int quantityBefore;
  final int quantityAfter;
  final String? reason;
  final String? reference;
  final String userId;
  final String userName;
  final String source; // scan, manual, pos
  final DateTime createdAt;
  final String shopId;

  const StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantityChange,
    required this.quantityBefore,
    required this.quantityAfter,
    this.reason,
    this.reference,
    required this.userId,
    required this.userName,
    required this.source,
    required this.createdAt,
    this.shopId = '',
  });

  bool get isStockIn => quantityChange > 0;
  bool get isStockOut => quantityChange < 0;

  StockMovement copyWith({
    String? id,
    String? productId,
    String? productName,
    String? type,
    int? quantityChange,
    int? quantityBefore,
    int? quantityAfter,
    String? reason,
    String? reference,
    String? userId,
    String? userName,
    String? source,
    DateTime? createdAt,
    String? shopId,
  }) {
    return StockMovement(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      type: type ?? this.type,
      quantityChange: quantityChange ?? this.quantityChange,
      quantityBefore: quantityBefore ?? this.quantityBefore,
      quantityAfter: quantityAfter ?? this.quantityAfter,
      reason: reason ?? this.reason,
      reference: reference ?? this.reference,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      shopId: shopId ?? this.shopId,
    );
  }

  @override
  List<Object?> get props => [id, productId, type, quantityChange, shopId];
}

/// Represents a sales transaction
class SaleTransaction extends Equatable {
  final String id;
  final String type; // sale, refund
  final List<SaleItem> items;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;
  final String paymentMethod;
  final String status; // completed_local, sync_pending, syncing, synced, sync_failed, conflict, voided
  final String? note;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final String? serverTransactionId;
  final String shopId;
  final String? operationId;
  final DateTime? syncedAt;
  final DateTime? lastSyncAttemptAt;
  final String? syncError;

  const SaleTransaction({
    required this.id,
    required this.type,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    required this.paymentMethod,
    required this.status,
    this.note,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.serverTransactionId,
    this.shopId = '',
    this.operationId,
    this.syncedAt,
    this.lastSyncAttemptAt,
    this.syncError,
  });

  SaleTransaction copyWith({
    String? id,
    String? type,
    List<SaleItem>? items,
    double? subtotal,
    double? discount,
    double? taxAmount,
    double? total,
    String? paymentMethod,
    String? status,
    String? note,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    String? serverTransactionId,
    String? shopId,
    String? operationId,
    DateTime? syncedAt,
    DateTime? lastSyncAttemptAt,
    String? syncError,
    bool clearSyncError = false,
  }) {
    return SaleTransaction(
      id: id ?? this.id,
      type: type ?? this.type,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      note: note ?? this.note,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      serverTransactionId: serverTransactionId ?? this.serverTransactionId,
      shopId: shopId ?? this.shopId,
      operationId: operationId ?? this.operationId,
      syncedAt: syncedAt ?? this.syncedAt,
      lastSyncAttemptAt: lastSyncAttemptAt ?? this.lastSyncAttemptAt,
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
    );
  }

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  @override
  List<Object?> get props => [
        id,
        total,
        items,
        status,
        serverTransactionId,
        shopId,
        operationId,
        syncedAt,
        lastSyncAttemptAt,
        syncError,
      ];
}

class SaleItem extends Equatable {
  final String productId;
  final String productName;
  final String sku;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  const SaleItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  @override
  List<Object?> get props => [productId, quantity, unitPrice];
}
