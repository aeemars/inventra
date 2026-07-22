import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final FirebaseFunctions _functions;

  ScannerRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

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

  // ── Sale (atomic stock deduction + records via Cloud Function) ──

  /// Performs an atomic sale via Cloud Function.
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
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final callable = _functions.httpsCallable('validateStockDeduction');
      final res = await callable.call({
        'shopId': shopId,
        'items': [
          {
            'productId': productId,
            'quantity': quantity,
          }
        ],
        'paymentMethod': 'cash',
        'discount': 0,
      });
      final resData = Map<String, dynamic>.from(res.data as Map);
      return resData['transactionId'] as String;
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'complete sale');
    }
  }

  // ── Restock (atomic stock increment + record via Cloud Function) ──

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
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final callable = _functions.httpsCallable('processRestock');
      await callable.call({
        'shopId': shopId,
        'productId': productId,
        'quantity': quantity,
        'note': note,
        'supplier': supplier,
      });
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'restock product');
    }
  }

  // ── Stock Adjustment (atomic via Cloud Function) ──

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
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final docRef = _firestore.collection(FirestorePaths.products(shopId)).doc(productId);
      final snap = await docRef.get();
      final currentQty = (snap.data()?['quantity'] as num?)?.toInt() ?? 0;
      final newQty = currentQty + quantityChange;

      final callable = _functions.httpsCallable('processStockAdjustment');
      await callable.call({
        'shopId': shopId,
        'productId': productId,
        'newQuantity': newQty < 0 ? 0 : newQty,
        'reason': reason,
      });
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'adjust stock');
    }
  }

  /// Performs an atomic multi-item sale via Cloud Function.
  Future<String> performMultiItemSale({
    required String shopId,
    required List<Map<String, dynamic>> items,
    required String userId,
    required String userName,
  }) async {
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final callable = _functions.httpsCallable('validateStockDeduction');
      final res = await callable.call({
        'shopId': shopId,
        'items': items,
        'paymentMethod': 'cash',
        'discount': 0,
      });
      final resData = Map<String, dynamic>.from(res.data as Map);
      return resData['transactionId'] as String;
    } on FirebaseException catch (e) {
      throw FirestoreFailure.fromCode(e.code, rawMessage: e.message);
    } catch (e) {
      throw handleFirestoreException(e, context: 'complete multi-item sale');
    }
  }
}
