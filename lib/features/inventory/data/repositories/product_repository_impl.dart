import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/firestore_error_handler.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/product_repository.dart';
import '../models/product_model.dart';

import 'package:cloud_functions/cloud_functions.dart';

class ProductRepositoryImpl implements ProductRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  ProductRepositoryImpl({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

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
    try {
      final doc = await _firestore
          .collection(FirestorePaths.products(shopId))
          .doc(productId)
          .get();
      if (!doc.exists) return null;
      return ProductModel.fromFirestore(doc).toEntity();
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'get product');
    }
  }

  @override
  Future<Product?> findByBarcode(String shopId, String barcode) async {
    try {
      final cleaned = _cleanLookup(barcode);
      if (cleaned.isEmpty) return null;

      // Build all candidate values to check:
      // EAN-13 (13 digits starting with 0) ↔ UPC-A (same 12 digits without leading 0)
      final candidates = <String>{cleaned};
      if (cleaned.length == 13 && cleaned.startsWith('0')) {
        candidates.add(cleaned.substring(1)); // strip leading zero → UPC-A
      }
      if (cleaned.length == 12) {
        candidates.add('0$cleaned'); // prepend zero → EAN-13
      }

      // 1. Search by barcode field for each candidate
      for (final candidate in candidates) {
        final q = await _firestore
            .collection(FirestorePaths.products(shopId))
            .where('barcode', isEqualTo: candidate)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          return ProductModel.fromFirestore(q.docs.first).toEntity();
        }
      }

      // 2. Search by sku field for each candidate
      for (final candidate in candidates) {
        final q = await _firestore
            .collection(FirestorePaths.products(shopId))
            .where('sku', isEqualTo: candidate)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          return ProductModel.fromFirestore(q.docs.first).toEntity();
        }
      }

      // 3. Last-resort: normalized full-collection scan
      final normalizedInput = _normalizedLookup(cleaned);
      if (normalizedInput.isEmpty) return null;

      final snapshot = await _firestore
          .collection(FirestorePaths.products(shopId))
          .get();

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
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'find product by barcode');
    }
  }

  @override
  Future<Product> addProduct(String shopId, Product product) async {
    try {
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
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'add product');
    }
  }

  @override
  Future<void> updateProduct(String shopId, Product product) async {
    try {
      final model = ProductModel.fromEntity(product);
      await _firestore
          .collection(FirestorePaths.products(shopId))
          .doc(product.id)
          .update(model.toFirestore());
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'update product');
    }
  }

  @override
  Future<void> deleteProduct(String shopId, String productId) async {
    try {
      await _firestore
          .collection(FirestorePaths.products(shopId))
          .doc(productId)
          .delete();
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'delete product');
    }
  }

  @override
  Future<void> updateStock(
      String shopId, String productId, int quantityChange) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final docRef =
            _firestore.collection(FirestorePaths.products(shopId)).doc(productId);
        final snapshot = await transaction.get(docRef);

        if (!snapshot.exists) {
          throw InventoryFailure.productNotFound();
        }

        final currentQty = (snapshot.data()!['quantity'] as num).toInt();
        final newQty = currentQty + quantityChange;

        if (newQty < 0) {
          throw InventoryFailure.insufficientStock(currentQty);
        }

        transaction.update(docRef, {
          'quantity': newQty,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on InventoryFailure {
      rethrow;
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'update stock');
    }
  }

  @override
  Future<void> restockWithRecord({
    required String shopId,
    required String productId,
    required String productName,
    required int quantity,
    required String userId,
  }) async {
    try {
      final callable = _functions.httpsCallable('processRestock');
      await callable.call({
        'shopId': shopId,
        'productId': productId,
        'quantity': quantity,
      });
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'restock product');
    }
  }

  @override
  Future<List<Product>> searchProducts(String shopId, String query) async {
    try {
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
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'search products');
    }
  }

  // ── Auto-generated Barcode ──

  @override
  Future<String> generateBarcode(String shopId) async {
    try {
      final counterRef = _firestore.doc('shops/$shopId/settings/barcode_counter');
      final newCount = await _firestore.runTransaction<int>((txn) async {
        final snap = await txn.get(counterRef);
        final current = (snap.data()?['value'] as int?) ?? 0;
        final next = current + 1;
        txn.set(counterRef, {'value': next}, SetOptions(merge: true));
        return next;
      });

      // Derive a stable 6-digit numeric prefix from the shop ID — this
      // keeps auto-generated barcodes unique across shops without
      // embedding the full, long Firestore document ID into the printed
      // barcode. All-numeric Code-128 encoding is roughly twice as dense
      // as alphanumeric, so this keeps the printed barcode short enough
      // to actually scan reliably at normal label sizes.
      final shopPrefix = _numericShopPrefix(shopId);
      final counterPart = newCount.toString().padLeft(6, '0');

      return '$shopPrefix$counterPart'; // 12 digits total
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'generate barcode');
    }
  }

  /// Deterministic 6-digit numeric code derived from a shop's Firestore
  /// document ID. Same shopId always produces the same prefix, and
  /// different shops produce different prefixes with negligible collision
  /// probability (1 in 900,000).
  String _numericShopPrefix(String shopId) {
    var hash = 0;
    for (final codeUnit in shopId.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7FFFFFFF;
    }
    final sixDigit = 100000 + (hash % 900000);
    return sixDigit.toString();
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
    try {
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
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'add category');
    }
  }

  @override
  Future<void> updateCategory(String shopId, Category category) async {
    try {
      await _firestore
          .collection(FirestorePaths.categories(shopId))
          .doc(category.id)
          .update({
        'name': category.name,
        'description': category.description,
      });
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'update category');
    }
  }

  @override
  Future<void> deleteCategory(String shopId, String categoryId) async {
    try {
      await _firestore
          .collection(FirestorePaths.categories(shopId))
          .doc(categoryId)
          .delete();
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'delete category');
    }
  }
}
