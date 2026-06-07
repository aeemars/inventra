import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/firestore_error_handler.dart';
import '../../../shared/models/scan_history_entry.dart';

/// Exception thrown when a sale would exceed available stock
class InsufficientStockException implements Exception {
  final int available;
  final int requested;

  const InsufficientStockException({
    required this.available,
    required this.requested,
  });

  @override
  String toString() =>
      'Insufficient stock. Available: $available, Requested: $requested';
}

class ScannerRepository {
  final FirebaseFirestore _firestore;

  ScannerRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Scan History ──

  Future<void> saveScanEntry(String shopId, ScanHistoryEntry entry) async {
    await _firestore
        .collection(FirestorePaths.scanHistory(shopId))
        .add(entry.toFirestore());
  }

  Stream<List<ScanHistoryEntry>> watchScanHistory(String shopId) {
    return _firestore
        .collection(FirestorePaths.scanHistory(shopId))
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ScanHistoryEntry.fromFirestore(doc))
            .toList());
  }

  // ── Sale (atomic stock deduction + records) ──

  /// Performs an atomic sale: validates stock, deducts quantity,
  /// creates stock_movement and transaction records.
  /// Returns the sale transaction ID.
  Future<String> performSale({
    required String shopId,
    required String productId,
    required String productName,
    required String productSku,
    required double unitPrice,
    required int quantity,
    required String userId,
    required String userName,
  }) async {
    try {
      final productRef = _firestore
          .collection(FirestorePaths.products(shopId))
          .doc(productId);

      // Pre-create doc refs so we can write inside the transaction
      final movementRef = _firestore
          .collection(FirestorePaths.stockMovements(shopId))
          .doc();
      final transactionRef = _firestore
          .collection(FirestorePaths.transactions(shopId))
          .doc();

      await _firestore.runTransaction((txn) async {
        final snapshot = await txn.get(productRef);
        if (!snapshot.exists) {
          throw ScannerFailure.productNotFound();
        }

        final currentQty = (snapshot.data()!['quantity'] as num).toInt();

        if (currentQty < quantity) {
          throw InsufficientStockException(
            available: currentQty,
            requested: quantity,
          );
        }

        final newQty = currentQty - quantity;
        final totalPrice = unitPrice * quantity;
        final now = FieldValue.serverTimestamp();

        // 1. Deduct stock
        txn.update(productRef, {
          'quantity': newQty,
          'updatedAt': now,
        });

        // 2. Create stock movement
        txn.set(movementRef, {
          'productId': productId,
          'productName': productName,
          'type': 'sale',
          'quantityChange': -quantity,
          'quantityBefore': currentQty,
          'quantityAfter': newQty,
          'reference': transactionRef.id,
          'userId': userId,
          'userName': userName,
          'source': 'scan',
          'createdAt': now,
        });

        // 3. Create sale transaction
        txn.set(transactionRef, {
          'type': 'sale',
          'items': [
            {
              'productId': productId,
              'productName': productName,
              'sku': productSku,
              'quantity': quantity,
              'unitPrice': unitPrice,
              'totalPrice': totalPrice,
            }
          ],
          'subtotal': totalPrice,
          'discount': 0,
          'taxAmount': 0,
          'total': totalPrice,
          'paymentMethod': 'pending',
          'status': 'completed',
          'createdBy': userId,
          'createdByName': userName,
          'createdAt': now,
        });
      });

      return transactionRef.id;
    } on ScannerFailure {
      rethrow;
    } on InsufficientStockException catch (e) {
      throw ScannerFailure.insufficientStock(e.available, e.requested);
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'complete sale');
    }
  }

  // ── Restock (atomic stock increment + record) ──

  /// Atomically increments stock and creates a stock movement record.
  Future<void> performRestock({
    required String shopId,
    required String productId,
    required String productName,
    required int quantity,
    required String userId,
    required String userName,
    String? note,
    String? supplier,
  }) async {
    try {
      final productRef = _firestore
          .collection(FirestorePaths.products(shopId))
          .doc(productId);
      final movementRef = _firestore
          .collection(FirestorePaths.stockMovements(shopId))
          .doc();

      await _firestore.runTransaction((txn) async {
        final snapshot = await txn.get(productRef);
        if (!snapshot.exists) {
          throw ScannerFailure.productNotFound();
        }

        final currentQty = (snapshot.data()!['quantity'] as num).toInt();
        final newQty = currentQty + quantity;
        final now = FieldValue.serverTimestamp();

        // 1. Increment stock
        txn.update(productRef, {
          'quantity': newQty,
          'updatedAt': now,
        });

        // 2. Create stock movement
        txn.set(movementRef, {
          'productId': productId,
          'productName': productName,
          'type': 'restock',
          'quantityChange': quantity,
          'quantityBefore': currentQty,
          'quantityAfter': newQty,
          'reason': note,
          'reference': supplier,
          'userId': userId,
          'userName': userName,
          'source': 'scan',
          'createdAt': now,
        });
      });
    } on ScannerFailure {
      rethrow;
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'restock product');
    }
  }

  // ── Stock Adjustment (atomic) ──

  Future<void> performAdjustment({
    required String shopId,
    required String productId,
    required String productName,
    required int quantityChange,
    required String userId,
    required String userName,
    String? reason,
  }) async {
    try {
      final productRef = _firestore
          .collection(FirestorePaths.products(shopId))
          .doc(productId);
      final movementRef = _firestore
          .collection(FirestorePaths.stockMovements(shopId))
          .doc();

      await _firestore.runTransaction((txn) async {
        final snapshot = await txn.get(productRef);
        if (!snapshot.exists) {
          throw ScannerFailure.productNotFound();
        }

        final currentQty = (snapshot.data()!['quantity'] as num).toInt();
        final newQty = currentQty + quantityChange;

        if (newQty < 0) {
          throw InsufficientStockException(
            available: currentQty,
            requested: quantityChange.abs(),
          );
        }

        final now = FieldValue.serverTimestamp();

        txn.update(productRef, {
          'quantity': newQty,
          'updatedAt': now,
        });

        txn.set(movementRef, {
          'productId': productId,
          'productName': productName,
          'type': 'adjustment',
          'quantityChange': quantityChange,
          'quantityBefore': currentQty,
          'quantityAfter': newQty,
          'reason': reason,
          'userId': userId,
          'userName': userName,
          'source': 'scan',
          'createdAt': now,
        });
      });
    } on ScannerFailure {
      rethrow;
    } on InsufficientStockException catch (e) {
      throw ScannerFailure.insufficientStock(e.available, e.requested);
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'adjust stock');
    }
  }
}
