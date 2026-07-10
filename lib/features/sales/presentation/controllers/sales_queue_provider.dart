import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../domain/sales_queue_item.dart';
import '../../../inventory/domain/entities/product.dart';

class SalesQueueNotifier extends StateNotifier<List<SalesQueueItem>> {
  SalesQueueNotifier() : super([]);

  /// Adds a product to the queue, or increments its quantity if already present.
  /// Clamps to available stock so the queue can never exceed on-hand quantity.
  void addOrIncrement(Product product, {int quantity = 1}) {
    final index = state.indexWhere((i) => i.product.id == product.id);
    if (index == -1) {
      final qty = quantity.clamp(1, product.quantity == 0 ? 1 : product.quantity);
      state = [...state, SalesQueueItem(product: product, quantity: qty)];
    } else {
      final existing = state[index];
      final newQty = (existing.quantity + quantity).clamp(1, product.quantity);
      final updated = [...state];
      updated[index] = existing.copyWith(quantity: newQty);
      state = updated;
    }
  }

  void updateQuantity(String productId, int quantity) {
    state = state.map((item) {
      if (item.product.id != productId) return item;
      final clamped = quantity.clamp(1, item.product.quantity);
      return item.copyWith(quantity: clamped);
    }).toList();
  }

  void removeItem(String productId) {
    state = state.where((i) => i.product.id != productId).toList();
  }

  void clear() => state = [];

  double get subtotal =>
      state.fold(0.0, (sum, item) => sum + item.lineTotal);

  int get itemCount => state.length;
}

final salesQueueProvider =
    StateNotifierProvider<SalesQueueNotifier, List<SalesQueueItem>>(
  (_) => SalesQueueNotifier(),
);

final salesQueueSubtotalProvider = Provider<double>((ref) {
  final items = ref.watch(salesQueueProvider);
  return items.fold(0.0, (sum, item) => sum + item.lineTotal);
});
