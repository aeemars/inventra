import 'package:cloud_firestore/cloud_firestore.dart';
import 'stock_movement.dart';

/// Firestore data model for StockMovement
class StockMovementModel {
  final String id;
  final String productId;
  final String productName;
  final String type;
  final int quantityChange;
  final int quantityBefore;
  final int quantityAfter;
  final String? reason;
  final String? reference;
  final String userId;
  final String userName;
  final String source;
  final DateTime createdAt;
  final String shopId;

  const StockMovementModel({
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

  factory StockMovementModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc, [String? explicitShopId]) {
    final d = doc.data()!;
    final resolvedShopId = explicitShopId ??
        d['shopId'] as String? ??
        (doc.reference.parent.parent != null
            ? doc.reference.parent.parent!.id
            : '');
    return StockMovementModel(
      id: doc.id,
      productId: d['productId'] as String? ?? '',
      productName: d['productName'] as String? ?? '',
      type: d['type'] as String? ?? 'adjustment',
      quantityChange: (d['quantityChange'] as num?)?.toInt() ?? 0,
      quantityBefore: (d['quantityBefore'] as num?)?.toInt() ?? 0,
      quantityAfter: (d['quantityAfter'] as num?)?.toInt() ?? 0,
      reason: d['reason'] as String?,
      reference: d['reference'] as String?,
      userId: d['userId'] as String? ?? '',
      userName: d['userName'] as String? ?? '',
      source: d['source'] as String? ?? 'manual',
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      shopId: resolvedShopId,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'productId': productId,
      'productName': productName,
      'type': type,
      'quantityChange': quantityChange,
      'quantityBefore': quantityBefore,
      'quantityAfter': quantityAfter,
      'reason': reason,
      'reference': reference,
      'userId': userId,
      'userName': userName,
      'source': source,
      'createdAt': FieldValue.serverTimestamp(),
      if (shopId.isNotEmpty) 'shopId': shopId,
    };
  }

  StockMovement toEntity([String? overrideShopId]) {
    return StockMovement(
      id: id,
      productId: productId,
      productName: productName,
      type: type,
      quantityChange: quantityChange,
      quantityBefore: quantityBefore,
      quantityAfter: quantityAfter,
      reason: reason,
      reference: reference,
      userId: userId,
      userName: userName,
      source: source,
      createdAt: createdAt,
      shopId: overrideShopId ?? shopId,
    );
  }

  static StockMovementModel fromEntity(StockMovement movement) {
    return StockMovementModel(
      id: movement.id,
      productId: movement.productId,
      productName: movement.productName,
      type: movement.type,
      quantityChange: movement.quantityChange,
      quantityBefore: movement.quantityBefore,
      quantityAfter: movement.quantityAfter,
      reason: movement.reason,
      reference: movement.reference,
      userId: movement.userId,
      userName: movement.userName,
      source: movement.source,
      createdAt: movement.createdAt,
      shopId: movement.shopId,
    );
  }
}
