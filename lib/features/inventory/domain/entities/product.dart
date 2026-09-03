import 'package:equatable/equatable.dart';

/// Domain entity for a Product
class Product extends Equatable {
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

  const Product({
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

  /// Generate search keywords from name and SKU for Firestore array-contains queries
  static List<String> generateKeywords(String name, String sku) {
    final keywords = <String>{};
    final nameLower = name.toLowerCase().trim();
    final skuLower = sku.toLowerCase().trim();

    // Add full name and SKU
    if (nameLower.isNotEmpty) keywords.add(nameLower);
    if (skuLower.isNotEmpty) keywords.add(skuLower);

    // Add individual words from name
    for (final word in nameLower.split(RegExp(r'\s+'))) {
      if (word.isNotEmpty) keywords.add(word);
    }

    // Add prefix substrings of name (for typeahead search)
    for (int i = 1; i <= nameLower.length && i <= 20; i++) {
      keywords.add(nameLower.substring(0, i));
    }

    return keywords.toList();
  }

  bool get isLowStock => quantity <= reorderLevel && quantity > 0;
  bool get isOutOfStock => quantity <= 0;
  double get inventoryValue => costPrice * quantity;
  double get potentialRevenue => sellingPrice * quantity;
  double get profit => sellingPrice - costPrice;
  double get profitMargin =>
      sellingPrice > 0 ? ((sellingPrice - costPrice) / sellingPrice * 100) : 0;

  Product copyWith({
    String? id,
    String? name,
    String? sku,
    String? barcode,
    String? categoryId,
    String? categoryName,
    double? costPrice,
    double? sellingPrice,
    int? quantity,
    int? reorderLevel,
    String? unit,
    String? supplier,
    String? imageUrl,
    String? description,
    DateTime? expiryDate,
    List<String>? searchKeywords,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? updatedBy,
    String? shopId,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      quantity: quantity ?? this.quantity,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      unit: unit ?? this.unit,
      supplier: supplier ?? this.supplier,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      expiryDate: expiryDate ?? this.expiryDate,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      shopId: shopId ?? this.shopId,
    );
  }

  @override
  List<Object?> get props =>
      [id, name, sku, barcode, quantity, sellingPrice, expiryDate, shopId];
}
