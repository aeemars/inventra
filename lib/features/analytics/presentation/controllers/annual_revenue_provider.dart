import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../inventory/presentation/controllers/inventory_controller.dart';
import '../../../transactions/presentation/controllers/transaction_logs_controller.dart';

/// Total revenue for the current calendar year (Jan 1 – Dec 31), used to
/// track progress against the Nigeria Tax Act 2025 small-company threshold.
final annualRevenueProvider = Provider<double>((ref) {
  final movements = ref.watch(stockMovementsProvider).value ?? [];
  final products = ref.watch(productsProvider).value ?? [];

  final priceMap = <String, double>{
    for (final p in products) p.name: p.sellingPrice,
  };

  final now = DateTime.now();
  final yearStart = DateTime(now.year, 1, 1);

  double total = 0;
  for (final m in movements) {
    if (m.isIntake) continue;
    if (m.createdAt.isBefore(yearStart)) continue;
    total += (priceMap[m.productName] ?? 0) * m.quantityChange.abs();
  }
  return total;
});
