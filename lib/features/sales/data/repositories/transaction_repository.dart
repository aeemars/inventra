import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../../../shared/models/stock_movement.dart';
import '../models/transaction_model.dart';
import '../../../../shared/models/stock_movement_model.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Repository for sales transactions and stock movement queries
class TransactionRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  TransactionRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  /// Process a sale via secure Cloud Function
  Future<Map<String, dynamic>> processSale({
    required String shopId,
    required List<Map<String, dynamic>> items,
    String paymentMethod = 'cash',
    double discount = 0.0,
    String? note,
  }) async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final callable = _functions.httpsCallable('validateStockDeduction');
    final response = await callable.call({
      'shopId': shopId,
      'items': items,
      'paymentMethod': paymentMethod,
      'discount': discount,
      'note': note,
    });
    return Map<String, dynamic>.from(response.data as Map);
  }

  // ── Transactions ──

  /// Watch all transactions for a shop, ordered by newest first
  Stream<List<SaleTransaction>> watchTransactions(String shopId) {
    return _firestore
        .collection(FirestorePaths.transactions(shopId))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Watch recent transactions (limited count)
  Stream<List<SaleTransaction>> watchRecentTransactions(
      String shopId, {int limit = 20}) {
    return _firestore
        .collection(FirestorePaths.transactions(shopId))
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Get a single transaction by ID
  Future<SaleTransaction?> getTransaction(
      String shopId, String transactionId) async {
    final doc = await _firestore
        .collection(FirestorePaths.transactions(shopId))
        .doc(transactionId)
        .get();
    if (!doc.exists) return null;
    return TransactionModel.fromFirestore(doc).toEntity();
  }

  /// Query transactions by date range
  Future<List<SaleTransaction>> getTransactionsByDateRange(
    String shopId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final snapshot = await _firestore
        .collection(FirestorePaths.transactions(shopId))
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('createdAt', isLessThan: Timestamp.fromDate(endDate))
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => TransactionModel.fromFirestore(doc).toEntity())
        .toList();
  }

  /// Query transactions by status
  Future<List<SaleTransaction>> getTransactionsByStatus(
      String shopId, String status) async {
    final snapshot = await _firestore
        .collection(FirestorePaths.transactions(shopId))
        .where('status', isEqualTo: status)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => TransactionModel.fromFirestore(doc).toEntity())
        .toList();
  }

  // ── Stock Movements ──

  /// Watch stock movements for a shop
  Stream<List<StockMovement>> watchStockMovements(String shopId) {
    return _firestore
        .collection(FirestorePaths.stockMovements(shopId))
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StockMovementModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Watch stock movements for a specific product
  Stream<List<StockMovement>> watchProductStockMovements(
      String shopId, String productId) {
    return _firestore
        .collection(FirestorePaths.stockMovements(shopId))
        .where('productId', isEqualTo: productId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StockMovementModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Get stock movements by date range
  Future<List<StockMovement>> getStockMovementsByDateRange(
    String shopId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final snapshot = await _firestore
        .collection(FirestorePaths.stockMovements(shopId))
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('createdAt', isLessThan: Timestamp.fromDate(endDate))
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => StockMovementModel.fromFirestore(doc).toEntity())
        .toList();
  }
}
