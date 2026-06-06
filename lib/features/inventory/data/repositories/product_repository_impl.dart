import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/product_repository.dart';
import '../models/product_model.dart';

class ProductRepositoryImpl implements ProductRepository {
  final FirebaseFirestore _firestore;

  ProductRepositoryImpl({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  String _cleanLookup(String value) => value.trim();

  String _normalizedLookup(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();

  @override
  Stream<List<Product>> watchProducts(String shopId) {
    return _firestore
        .collection(FirestorePaths.products(shopId))
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ProductModel.fromFirestore(doc).toEntity())
            .toList());
  }

  @override
  Future<Product?> getProduct(String shopId, String productId) async {
    final doc = await _firestore
        .collection(FirestorePaths.products(shopId))
        .doc(productId)
        .get();
    if (!doc.exists) return null;
    return ProductModel.fromFirestore(doc).toEntity();
  }

  @override
  Future<Product?> findByBarcode(String shopId, String barcode) async {
    final cleanedBarcode = _cleanLookup(barcode);
    if (cleanedBarcode.isEmpty) return null;

    // Search by barcode field first
    var query = await _firestore
        .collection(FirestorePaths.products(shopId))
        .where('barcode', isEqualTo: cleanedBarcode)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return ProductModel.fromFirestore(query.docs.first).toEntity();
    }

    // Fallback: search by SKU
    query = await _firestore
        .collection(FirestorePaths.products(shopId))
        .where('sku', isEqualTo: cleanedBarcode)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return ProductModel.fromFirestore(query.docs.first).toEntity();
    }

    // Last-resort fallback for formatting mismatches (spaces, hyphens, case).
    final normalizedInput = _normalizedLookup(cleanedBarcode);
    if (normalizedInput.isEmpty) return null;

    final snapshot =
        await _firestore.collection(FirestorePaths.products(shopId)).get();

    for (final doc in snapshot.docs) {
      final model = ProductModel.fromFirestore(doc);
      final normalizedSku = _normalizedLookup(model.sku);
      final normalizedBarcode =
          model.barcode == null ? '' : _normalizedLookup(model.barcode!);

      if (normalizedInput == normalizedSku ||
          (normalizedBarcode.isNotEmpty &&
              normalizedInput == normalizedBarcode)) {
        return model.toEntity();
      }
    }

    return null;
  }

  @override
  Future<Product> addProduct(String shopId, Product product) async {
    final batch = _firestore.batch();

    final docRef = _firestore.collection(FirestorePaths.products(shopId)).doc();
    final newProduct = product.copyWith(id: docRef.id);
    batch.set(docRef, ProductModel.fromEntity(newProduct).toFirestore());

    if (product.quantity > 0) {
      final movementRef = _firestore
          .collection(FirestorePaths.stockMovements(shopId))
          .doc();
      batch.set(movementRef, {
        'productId': docRef.id,
        'productName': product.name,
        'type': 'intake',
        'quantityChange': product.quantity,
        'quantityBefore': 0,
        'quantityAfter': product.quantity,
        'reason': 'Initial stock',
        'userId': product.createdBy,
        'userName': '',
        'source': 'manual',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return newProduct;
  }

  @override
  Future<void> updateProduct(String shopId, Product product) async {
    final model = ProductModel.fromEntity(product);
    await _firestore
        .collection(FirestorePaths.products(shopId))
        .doc(product.id)
        .update(model.toFirestore());
  }

  @override
  Future<void> deleteProduct(String shopId, String productId) async {
    await _firestore
        .collection(FirestorePaths.products(shopId))
        .doc(productId)
        .delete();
  }

  @override
  Future<void> updateStock(
      String shopId, String productId, int quantityChange) async {
    await _firestore.runTransaction((transaction) async {
      final docRef =
          _firestore.collection(FirestorePaths.products(shopId)).doc(productId);
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists) {
        throw Exception('Product not found');
      }

      final currentQty = (snapshot.data()!['quantity'] as num).toInt();
      final newQty = currentQty + quantityChange;

      if (newQty < 0) {
        throw Exception('Insufficient stock. Available: $currentQty');
      }

      transaction.update(docRef, {
        'quantity': newQty,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> restockWithRecord({
    required String shopId,
    required String productId,
    required String productName,
    required int quantity,
    required String userId,
  }) async {
    final productRef = _firestore
        .collection(FirestorePaths.products(shopId))
        .doc(productId);
    final movementRef = _firestore
        .collection(FirestorePaths.stockMovements(shopId))
        .doc();

    await _firestore.runTransaction((txn) async {
      final snapshot = await txn.get(productRef);
      if (!snapshot.exists) throw Exception('Product not found');

      final currentQty = (snapshot.data()!['quantity'] as num).toInt();
      final newQty = currentQty + quantity;
      final now = FieldValue.serverTimestamp();

      txn.update(productRef, {'quantity': newQty, 'updatedAt': now});
      txn.set(movementRef, {
        'productId': productId,
        'productName': productName,
        'type': 'intake',
        'quantityChange': quantity,
        'quantityBefore': currentQty,
        'quantityAfter': newQty,
        'reason': 'Manual restock',
        'userId': userId,
        'userName': '',
        'source': 'manual',
        'createdAt': now,
      });
    });
  }

  @override
  Future<List<Product>> searchProducts(String shopId, String query) async {
    // Firestore doesn't support full-text search natively.
    // We fetch all and filter client-side for now.
    // For production, use Algolia or Typesense integration.
    final snapshot =
        await _firestore.collection(FirestorePaths.products(shopId)).get();

    final lowerQuery = query.toLowerCase();
    return snapshot.docs
        .map((doc) => ProductModel.fromFirestore(doc).toEntity())
        .where((p) =>
            p.name.toLowerCase().contains(lowerQuery) ||
            p.sku.toLowerCase().contains(lowerQuery) ||
            (p.barcode?.toLowerCase().contains(lowerQuery) ?? false))
        .toList();
  }

  // ── Categories ──

  @override
  Stream<List<Category>> watchCategories(String shopId) {
    return _firestore
        .collection(FirestorePaths.categories(shopId))
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return Category(
                id: doc.id,
                name: data['name'] as String? ?? '',
                description: data['description'] as String?,
                productCount: (data['productCount'] as num?)?.toInt() ?? 0,
                createdAt: (data['createdAt'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
                updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
              );
            }).toList());
  }

  @override
  Future<Category> addCategory(String shopId, Category category) async {
    final docRef =
        _firestore.collection(FirestorePaths.categories(shopId)).doc();
    await docRef.set({
      'name': category.name,
      'description': category.description,
      'productCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return category.copyWith(id: docRef.id, updatedAt: DateTime.now());
  }

  @override
  Future<void> updateCategory(String shopId, Category category) async {
    await _firestore
        .collection(FirestorePaths.categories(shopId))
        .doc(category.id)
        .update({
      'name': category.name,
      'description': category.description,
    });
  }

  @override
  Future<void> deleteCategory(String shopId, String categoryId) async {
    await _firestore
        .collection(FirestorePaths.categories(shopId))
        .doc(categoryId)
        .delete();
  }
}
