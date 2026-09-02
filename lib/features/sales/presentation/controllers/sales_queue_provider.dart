import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../domain/sales_queue_item.dart';
import '../../../inventory/domain/entities/product.dart';

import '../../../../core/cache/local_database.dart';

class SalesQueueNotifier extends StateNotifier<List<SalesQueueItem>> {
  final LocalDatabase _localDb;

  SalesQueueNotifier([LocalDatabase? localDb])
      : _localDb = localDb ?? LocalDatabase.instance,
        super([]) {
    _loadFromLocal();
  }

  void _loadFromLocal() {
    if (_localDb.isInitialized) {
      state = _localDb.salesQueueBox.values.toList();
    }
  }

  /// Adds a product to the queue, or increments its quantity if already present.
  /// Clamps to available stock so the queue can never exceed on-hand quantity.
  void addOrIncrement(Product product, {int quantity = 1}) {
    final index = state.indexWhere((i) => i.product.id == product.id);
    SalesQueueItem item;
    if (index == -1) {
      final qty = quantity.clamp(1, product.quantity == 0 ? 1 : product.quantity);
      item = SalesQueueItem(product: product, quantity: qty);
      state = [...state, item];
    } else {
      final existing = state[index];
      final newQty = (existing.quantity + quantity).clamp(1, product.quantity);
      item = existing.copyWith(quantity: newQty);
      final updated = [...state];
      updated[index] = item;
      state = updated;
    }
    if (_localDb.isInitialized) {
      _localDb.salesQueueBox.put(product.id, item);
    }
  }

  /// Adds a product to the queue ONLY if it is not already in the queue.
  /// Returns `true` if newly added, `false` if product was already in the queue.
  bool addUnique(Product product, {int quantity = 1}) {
    final index = state.indexWhere((i) => i.product.id == product.id);
    if (index != -1) {
      return false; // Already present in queue
    }
    final qty = quantity.clamp(1, product.quantity == 0 ? 1 : product.quantity);
    final item = SalesQueueItem(product: product, quantity: qty);
    state = [...state, item];
    if (_localDb.isInitialized) {
      _localDb.salesQueueBox.put(product.id, item);
    }
    return true;
  }

  void updateQuantity(String productId, int quantity) {
    state = state.map((item) {
      if (item.product.id != productId) return item;
      final clamped = quantity.clamp(1, item.product.quantity);
      final updated = item.copyWith(quantity: clamped);
      if (_localDb.isInitialized) {
        _localDb.salesQueueBox.put(productId, updated);
      }
      return updated;
    }).toList();
  }

  void removeItem(String productId) {
    state = state.where((i) => i.product.id != productId).toList();
    if (_localDb.isInitialized) {
      _localDb.salesQueueBox.delete(productId);
    }
  }

  Future<void> clear() async {
    state = [];
    if (_localDb.isInitialized) {
      await _localDb.salesQueueBox.clear();
    }
  }

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
