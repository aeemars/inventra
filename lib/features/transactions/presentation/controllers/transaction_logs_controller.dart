import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../shared/providers/firebase_providers.dart';
import '../../../../core/cache/local_database.dart';


/// Represents a single transaction log entry for display
class TransactionLogEntry {
  final String id;
  final String productName;
  final String type; // 'intake' or 'sale'
  final String typeLabel; // 'Inventory Intake', 'Sales Order'
  final String referenceId;
  final int quantityChange;
  final DateTime createdAt;
  final String? syncStatus;

  const TransactionLogEntry({
    required this.id,
    required this.productName,
    required this.type,
    required this.typeLabel,
    required this.referenceId,
    required this.quantityChange,
    required this.createdAt,
    this.syncStatus,
  });

  bool get isIntake => quantityChange > 0;
}

/// Filter for transaction logs
enum TransactionFilter { all, intake, sales }

final transactionFilterProvider =
    StateProvider<TransactionFilter>((ref) => TransactionFilter.all);

/// Stream stock movements from LocalDatabase (cached + local) ordered by creation date
final stockMovementsProvider =
    StreamProvider<List<TransactionLogEntry>>((ref) {
  final shopId = ref.watch(currentShopIdProvider);
  if (shopId == null) return Stream.value([]);

  final localDb = LocalDatabase.instance;
  if (!localDb.isInitialized) return Stream.value([]);

  return Stream<List<TransactionLogEntry>>.multi((controller) {
    void emitLocal() {
      final list = localDb.stockMovementsBox.values
          .where((m) => m.shopId == shopId || m.shopId.isEmpty)
          .map((m) {
        final qtyChange = m.quantityChange;
        final type = qtyChange > 0 ? 'intake' : 'sale';
        final typeLabel = qtyChange > 0 ? 'Inventory Intake' : 'Sales Order';
        final refId =
            m.reference ?? (m.id.length >= 8 ? m.id.substring(0, 8) : m.id);

        final tx = m.reference != null
            ? localDb.getTransaction(shopId, m.reference!)
            : null;

        return TransactionLogEntry(
          id: m.id,
          productName: m.productName,
          type: type,
          typeLabel: typeLabel,
          referenceId: refId,
          quantityChange: qtyChange,
          createdAt: m.createdAt,
          syncStatus: tx?.status,
        );
      }).toList();

      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(list.take(100).toList());
    }

    emitLocal();
    final sub = localDb.stockMovementsBox.watch().listen((_) => emitLocal());
    controller.onCancel = () => sub.cancel();
  });
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
