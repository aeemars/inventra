import 'package:equatable/equatable.dart';

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
  });

  bool get isStockIn => quantityChange > 0;
  bool get isStockOut => quantityChange < 0;

  @override
  List<Object?> get props => [id, productId, type, quantityChange];
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
  final String status; // completed, pending, cancelled
  final String? note;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final String? serverTransactionId;

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
    );
  }

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  @override
  List<Object?> get props => [id, total, items, status, serverTransactionId];
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
