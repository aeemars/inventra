import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../../shared/providers/firebase_providers.dart';
export '../../../../shared/providers/firebase_providers.dart' show currentShopIdProvider;

// ── Repository Provider ──
final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepositoryImpl();
});

// ── Products Stream ──
final productsProvider = StreamProvider<List<Product>>((ref) {
  final shopId = ref.watch(currentShopIdProvider);
  if (shopId == null) return Stream.value([]);
  return ref.watch(productRepositoryProvider).watchProducts(shopId);
});

// ── Search / Filter ──
final productSearchQueryProvider = StateProvider<String>((ref) => '');
final productCategoryFilterProvider = StateProvider<String?>((ref) => null);
final productSortProvider =
    StateProvider<ProductSort>((ref) => ProductSort.newest);

enum ProductSort {
  newest,
  oldest,
  nameAZ,
  nameZA,
  priceLowHigh,
  priceHighLow,
  stockLowHigh
}

final filteredProductsProvider = Provider<List<Product>>((ref) {
  final productsAsync = ref.watch(productsProvider);
  final searchQuery = ref.watch(productSearchQueryProvider).toLowerCase();
  final categoryFilter = ref.watch(productCategoryFilterProvider);
  final sort = ref.watch(productSortProvider);

  return productsAsync.when(
    data: (products) {
      var filtered = products.where((p) => p.isActive).toList();

      // Search
      if (searchQuery.isNotEmpty) {
        filtered = filtered
            .where((p) =>
                p.name.toLowerCase().contains(searchQuery) ||
                p.sku.toLowerCase().contains(searchQuery) ||
                (p.barcode?.toLowerCase().contains(searchQuery) ?? false))
            .toList();
      }

      // Category filter
      if (categoryFilter != null) {
        filtered =
            filtered.where((p) => p.categoryId == categoryFilter).toList();
      }

      // Sort
      switch (sort) {
        case ProductSort.newest:
          filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          break;
        case ProductSort.oldest:
          filtered.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
          break;
        case ProductSort.nameAZ:
          filtered.sort((a, b) => a.name.compareTo(b.name));
          break;
        case ProductSort.nameZA:
          filtered.sort((a, b) => b.name.compareTo(a.name));
          break;
        case ProductSort.priceLowHigh:
          filtered.sort((a, b) => a.sellingPrice.compareTo(b.sellingPrice));
          break;
        case ProductSort.priceHighLow:
          filtered.sort((a, b) => b.sellingPrice.compareTo(a.sellingPrice));
          break;
        case ProductSort.stockLowHigh:
          filtered.sort((a, b) => a.quantity.compareTo(b.quantity));
          break;
      }

      return filtered;
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

// ── Stats ──
final totalProductsProvider = Provider<int>((ref) {
  final products = ref.watch(productsProvider).value ?? [];
  return products.where((p) => p.isActive).length;
});

final lowStockProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(productsProvider).value ?? [];
  return products.where((p) => p.isLowStock || p.isOutOfStock).toList();
});

final lowStockCountProvider = Provider<int>((ref) {
  return ref.watch(lowStockProductsProvider).length;
});

final inventoryValueProvider = Provider<double>((ref) {
  final products = ref.watch(productsProvider).value ?? [];
  return products.fold(0.0, (sum, p) => sum + p.inventoryValue);
});

// ── Inventory Controller ──
final inventoryControllerProvider =
    StateNotifierProvider<InventoryController, InventoryState>((ref) {
  return InventoryController(
    ref.watch(productRepositoryProvider),
    ref,
  );
});

@immutable
class InventoryState {
  final bool isLoading;
  final String? error;
  final bool isSuccess;

  const InventoryState({
    this.isLoading = false,
    this.error,
    this.isSuccess = false,
  });

  InventoryState copyWith({bool? isLoading, String? error, bool? isSuccess}) {
    return InventoryState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}

class InventoryController extends StateNotifier<InventoryState> {
  final ProductRepository _repository;
  final Ref _ref;

  InventoryController(this._repository, this._ref)
      : super(const InventoryState());

  String? get _shopId => _ref.read(currentShopIdProvider);

  Future<Product?> addProduct(Product product) async {
    if (_shopId == null) {
      state = state.copyWith(error: InventoryFailure.noShop().message);
      return null;
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repository.addProduct(_shopId!, product);
      state = state.copyWith(isLoading: false, isSuccess: true);
      return result;
    } on Failure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return null;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to add product. Please try again.',
      );
      return null;
    }
  }

  Future<bool> updateProduct(Product product) async {
    if (_shopId == null) {
      state = state.copyWith(error: InventoryFailure.noShop().message);
      return false;
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.updateProduct(_shopId!, product);
      state = state.copyWith(isLoading: false, isSuccess: true);
      return true;
    } on Failure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to update product. Please try again.',
      );
      return false;
    }
  }

  Future<bool> deleteProduct(String productId) async {
    if (_shopId == null) {
      state = state.copyWith(error: InventoryFailure.noShop().message);
      return false;
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.deleteProduct(_shopId!, productId);
      state = state.copyWith(isLoading: false, isSuccess: true);
      return true;
    } on Failure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to delete product. Please try again.',
      );
      return false;
    }
  }

  Future<bool> adjustStock(String productId, int change, {String productName = ''}) async {
    if (_shopId == null) {
      state = state.copyWith(error: InventoryFailure.noShop().message);
      return false;
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      final userId = _ref.read(currentUserProvider)?.uid ?? '';
      if (change > 0) {
        // Restock — use the method that writes a stock_movements record
        await _repository.restockWithRecord(
          shopId: _shopId!,
          productId: productId,
          productName: productName,
          quantity: change,
          userId: userId,
        );
      } else {
        // Negative adjustment — plain stock update (no sale record)
        await _repository.updateStock(_shopId!, productId, change);
      }
      state = state.copyWith(isLoading: false, isSuccess: true);
      return true;
    } on Failure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to update stock level. Please try again.',
      );
      return false;
    }
  }
}
