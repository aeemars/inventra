import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/product.dart';

/// Firestore data model for Product
class ProductModel {
  final String id;
  final String name;
  final String sku;
  final String? barcode;
  final String? categoryId;
  final String? categoryName;
  final double costPrice;
  final double sellingPrice;
  final int quantity;
  final int reorderLevel;
  final String unit;
  final String? supplier;
  final String? imageUrl;
  final String? description;
  final DateTime? expiryDate;
  final bool isActive;
  final List<String> searchKeywords;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;
  final String shopId;

  const ProductModel({
    required this.id,
    required this.name,
    required this.sku,
    this.barcode,
    this.categoryId,
    this.categoryName,
    required this.costPrice,
    required this.sellingPrice,
    required this.quantity,
    required this.reorderLevel,
    this.unit = 'pcs',
    this.supplier,
    this.imageUrl,
    this.description,
    this.expiryDate,
    this.isActive = true,
    this.searchKeywords = const [],
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    this.shopId = '',
  });

  factory ProductModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc, [String? explicitShopId]) {
    final data = doc.data()!;
    final resolvedShopId = explicitShopId ??
        data['shopId'] as String? ??
        (doc.reference.parent.parent != null
            ? doc.reference.parent.parent!.id
            : '');

    return ProductModel(
      id: doc.id,
      name: data['name'] as String? ?? '',
      sku: data['sku'] as String? ?? '',
      barcode: data['barcode'] as String?,
      categoryId: data['categoryId'] as String?,
      categoryName: data['categoryName'] as String?,
      costPrice: (data['costPrice'] as num?)?.toDouble() ?? 0,
      sellingPrice: (data['sellingPrice'] as num?)?.toDouble() ?? 0,
      quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      reorderLevel: (data['reorderLevel'] as num?)?.toInt() ?? 5,
      unit: data['unit'] as String? ?? 'pcs',
      supplier: data['supplier'] as String?,
      imageUrl: data['imageUrl'] as String?,
      description: data['description'] as String?,
      expiryDate: (data['expiryDate'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] as bool? ?? true,
      searchKeywords: (data['searchKeywords'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] as String? ?? '',
      updatedBy: data['updatedBy'] as String? ?? '',
      shopId: resolvedShopId,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'sku': sku,
      'barcode': barcode,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'costPrice': costPrice,
      'sellingPrice': sellingPrice,
      'quantity': quantity,
      'reorderLevel': reorderLevel,
      'unit': unit,
      'supplier': supplier,
      'imageUrl': imageUrl,
      'description': description,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
      'isActive': isActive,
      'searchKeywords': searchKeywords,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      if (shopId.isNotEmpty) 'shopId': shopId,
    };
  }

  Product toEntity([String? overrideShopId]) {
    return Product(
      id: id,
      name: name,
      sku: sku,
      barcode: barcode,
      categoryId: categoryId,
      categoryName: categoryName,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      quantity: quantity,
      reorderLevel: reorderLevel,
      unit: unit,
      supplier: supplier,
      imageUrl: imageUrl,
      description: description,
      expiryDate: expiryDate,
      isActive: isActive,
      searchKeywords: searchKeywords,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy,
      shopId: overrideShopId ?? shopId,
    );
  }

  static ProductModel fromEntity(Product product) {
    return ProductModel(
      id: product.id,
      name: product.name,
      sku: product.sku,
      barcode: product.barcode,
      categoryId: product.categoryId,
      categoryName: product.categoryName,
      costPrice: product.costPrice,
      sellingPrice: product.sellingPrice,
      quantity: product.quantity,
      reorderLevel: product.reorderLevel,
      unit: product.unit,
      supplier: product.supplier,
      imageUrl: product.imageUrl,
      description: product.description,
      expiryDate: product.expiryDate,
      isActive: product.isActive,
      searchKeywords: product.searchKeywords.isNotEmpty
          ? product.searchKeywords
          : Product.generateKeywords(product.name, product.sku),
      createdAt: product.createdAt,
      updatedAt: product.updatedAt,
      createdBy: product.createdBy,
      updatedBy: product.updatedBy,
      shopId: product.shopId,
    );
  }
}
