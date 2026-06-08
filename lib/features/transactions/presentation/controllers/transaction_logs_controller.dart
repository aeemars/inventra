import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../shared/providers/firebase_providers.dart';


/// Represents a single transaction log entry for display
class TransactionLogEntry {
  final String id;
  final String productName;
  final String type; // 'intake' or 'sale'
  final String typeLabel; // 'Inventory Intake', 'Sales Order'
  final String referenceId;
  final int quantityChange;
  final DateTime createdAt;

  const TransactionLogEntry({
    required this.id,
    required this.productName,
    required this.type,
    required this.typeLabel,
    required this.referenceId,
    required this.quantityChange,
    required this.createdAt,
  });

  bool get isIntake => quantityChange > 0;
}

/// Filter for transaction logs
enum TransactionFilter { all, intake, sales }

final transactionFilterProvider =
    StateProvider<TransactionFilter>((ref) => TransactionFilter.all);

/// Stream stock movements from Firestore ordered by creation date
final stockMovementsProvider =
    StreamProvider<List<TransactionLogEntry>>((ref) {
  final shopId = ref.watch(currentShopIdProvider);
  if (shopId == null) return Stream.value([]);

  final firestore = ref.watch(firestoreProvider);

  return firestore
      .collection('shops/$shopId/stock_movements')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            final qtyChange = (data['quantityChange'] as num?)?.toInt() ?? 0;
            final type = qtyChange > 0 ? 'intake' : 'sale';
            final typeLabel =
                qtyChange > 0 ? 'Inventory Intake' : 'Sales Order';

            return TransactionLogEntry(
              id: doc.id,
              productName: data['productName'] as String? ?? 'Unknown Product',
              type: type,
              typeLabel: typeLabel,
              referenceId: data['reference'] as String? ?? doc.id.substring(0, 8),
              quantityChange: qtyChange,
              createdAt: (data['createdAt'] as Timestamp?)?.toDate() ??
                  DateTime.now(),
            );
          }).toList());
});

/// Filtered transaction logs
final filteredTransactionLogsProvider =
    Provider<List<TransactionLogEntry>>((ref) {
  final logsAsync = ref.watch(stockMovementsProvider);
  final filter = ref.watch(transactionFilterProvider);

  return logsAsync.when(
    data: (logs) {
      switch (filter) {
        case TransactionFilter.all:
          return logs;
        case TransactionFilter.intake:
          return logs.where((l) => l.isIntake).toList();
        case TransactionFilter.sales:
          return logs.where((l) => !l.isIntake).toList();
      }
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Today's intake count
final todayIntakeCountProvider = Provider<int>((ref) {
  final logsAsync = ref.watch(stockMovementsProvider);
  return logsAsync.when(
    data: (logs) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      return logs
          .where((l) =>
              l.isIntake && l.createdAt.isAfter(todayStart))
          .fold<int>(0, (total, l) => total + l.quantityChange);
    },
    loading: () => 0,
    error: (_, __) => 0,
  );
});

/// Today's sales count
final todaySalesCountProvider = Provider<int>((ref) {
  final logsAsync = ref.watch(stockMovementsProvider);
  return logsAsync.when(
    data: (logs) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      return logs
          .where((l) =>
              !l.isIntake && l.createdAt.isAfter(todayStart))
          .fold<int>(0, (total, l) => total + l.quantityChange.abs());
    },
    loading: () => 0,
    error: (_, __) => 0,
  );
});
