import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../core/errors/failures.dart';
import '../../../../shared/models/scan_history_entry.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../inventory/presentation/controllers/inventory_controller.dart';
import '../../data/scanner_repository.dart';
import '../../../sales/domain/sales_queue_item.dart';

// ── Repository Provider ──
final scannerRepositoryProvider = Provider<ScannerRepository>((ref) {
  return ScannerRepository();
});

// ── Scan History Stream ──
final scanHistoryProvider = StreamProvider<List<ScanHistoryEntry>>((ref) {
  final shopId = ref.watch(currentShopIdProvider);
  if (shopId == null) return Stream.value([]);
  return ref.watch(scannerRepositoryProvider).watchScanHistory(shopId);
});

// ── Scanner Action Controller ──
final scannerControllerProvider =
    StateNotifierProvider<ScannerController, ScannerActionState>((ref) {
  return ScannerController(ref);
});

@immutable
class ScannerActionState {
  final ScannerStatus status;
  final String? message;

  const ScannerActionState({
    this.status = ScannerStatus.idle,
    this.message,
  });

  bool get isLoading => status == ScannerStatus.loading;
  bool get isSuccess => status == ScannerStatus.success;
  bool get isError => status == ScannerStatus.error;

  ScannerActionState copyWith({ScannerStatus? status, String? message}) {
    return ScannerActionState(
      status: status ?? this.status,
      message: message,
    );
  }

  static const idle = ScannerActionState();
}

enum ScannerStatus { idle, loading, success, error }

class ScannerController extends StateNotifier<ScannerActionState> {
  final Ref _ref;

  ScannerController(this._ref) : super(ScannerActionState.idle);

  String? get _shopId => _ref.read(currentShopIdProvider);

  String get _userId =>
      _ref.read(currentUserProvider)?.uid ?? '';

  String get _userName =>
      _ref.read(currentUserProvider)?.displayName ?? 'Unknown';

  void reset() => state = ScannerActionState.idle;

  /// Save a scan event to history
  Future<void> saveScanEntry({
    required String barcodeValue,
    required String scanIntent,
    String? matchedProductId,
    String? matchedProductName,
  }) async {
    final shopId = _shopId;
    if (shopId == null) return;

    final entry = ScanHistoryEntry(
      id: '',
      barcodeValue: barcodeValue,
      matchedProductId: matchedProductId,
      matchedProductName: matchedProductName,
      status: matchedProductId != null
          ? ScanMatchStatus.matched
          : ScanMatchStatus.unmatched,
      scanIntent: scanIntent,
      scannedBy: _userId,
      scannedByName: _userName,
      timestamp: DateTime.now(),
    );

    try {
      await _ref.read(scannerRepositoryProvider).saveScanEntry(shopId, entry);
    } catch (_) {
      // Non-critical: don't block scanner flow if history save fails
    }
  }

  /// Perform a sale with stock validation
  Future<bool> sellProduct({
    required String productId,
    required String productName,
    required String productSku,
    required double unitPrice,
    required int quantity,
  }) async {
    final shopId = _shopId;
    if (shopId == null) {
      state = state.copyWith(
        status: ScannerStatus.error,
        message: ScannerFailure.noShop().message,
      );
      return false;
    }

    state = state.copyWith(status: ScannerStatus.loading);

    try {
      await _ref.read(scannerRepositoryProvider).performSale(
            shopId: shopId,
            productId: productId,
            productName: productName,
            productSku: productSku,
            unitPrice: unitPrice,
            quantity: quantity,
            userId: _userId,
            userName: _userName,
          );

      final total = unitPrice * quantity;
      state = state.copyWith(
        status: ScannerStatus.success,
        message:
            'Sale complete: $quantity × $productName = ₦${total.toStringAsFixed(2)}',
      );
      return true;
    } on ScannerFailure catch (e) {
      state = state.copyWith(status: ScannerStatus.error, message: e.message);
      return false;
    } on Failure catch (e) {
      state = state.copyWith(status: ScannerStatus.error, message: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        status: ScannerStatus.error,
        message: ScannerFailure.saleFailed().message,
      );
      return false;
    }
  }

  /// Perform a restock with atomic increment
  Future<bool> restockProduct({
    required String productId,
    required String productName,
    required int quantity,
    String? note,
    String? supplier,
  }) async {
    final shopId = _shopId;
    if (shopId == null) {
      state = state.copyWith(
        status: ScannerStatus.error,
        message: ScannerFailure.noShop().message,
      );
      return false;
    }

    state = state.copyWith(status: ScannerStatus.loading);

    try {
      await _ref.read(scannerRepositoryProvider).performRestock(
            shopId: shopId,
            productId: productId,
            productName: productName,
            quantity: quantity,
            userId: _userId,
            userName: _userName,
            note: note,
            supplier: supplier,
          );

      state = state.copyWith(
        status: ScannerStatus.success,
        message: 'Restocked $quantity units of $productName',
      );
      return true;
    } on ScannerFailure catch (e) {
      state = state.copyWith(status: ScannerStatus.error, message: e.message);
      return false;
    } on Failure catch (e) {
      state = state.copyWith(status: ScannerStatus.error, message: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        status: ScannerStatus.error,
        message: ScannerFailure.restockFailed().message,
      );
      return false;
    }
  }

  /// Perform a stock adjustment
  Future<bool> adjustStock({
    required String productId,
    required String productName,
    required int quantityChange,
    String? reason,
  }) async {
    final shopId = _shopId;
    if (shopId == null) {
      state = state.copyWith(
        status: ScannerStatus.error,
        message: ScannerFailure.noShop().message,
      );
      return false;
    }

    state = state.copyWith(status: ScannerStatus.loading);

    try {
      await _ref.read(scannerRepositoryProvider).performAdjustment(
            shopId: shopId,
            productId: productId,
            productName: productName,
            quantityChange: quantityChange,
            userId: _userId,
            userName: _userName,
            reason: reason,
          );

      final sign = quantityChange > 0 ? '+' : '';
      state = state.copyWith(
        status: ScannerStatus.success,
        message: 'Adjusted $productName: $sign$quantityChange',
      );
      return true;
    } on ScannerFailure catch (e) {
      state = state.copyWith(status: ScannerStatus.error, message: e.message);
      return false;
    } on Failure catch (e) {
      state = state.copyWith(status: ScannerStatus.error, message: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        status: ScannerStatus.error,
        message: ScannerFailure.adjustmentFailed().message,
      );
      return false;
    }
  }

  Future<bool> completeMultiItemSale(List<SalesQueueItem> queue) async {
    final shopId = _shopId;
    if (shopId == null) {
      state = state.copyWith(
        status: ScannerStatus.error,
        message: ScannerFailure.noShop().message,
      );
      return false;
    }

    state = state.copyWith(status: ScannerStatus.loading);

    try {
      final items = queue
          .map((i) => {
                'productId': i.product.id,
                'productName': i.product.name,
                'sku': i.product.sku,
                'quantity': i.quantity,
                'unitPrice': i.product.sellingPrice,
              })
          .toList();

      await _ref.read(scannerRepositoryProvider).performMultiItemSale(
            shopId: shopId,
            items: items,
            userId: _userId,
            userName: _userName,
          );

      final total = queue.fold(0.0, (sum, i) => sum + i.lineTotal);
      state = state.copyWith(
        status: ScannerStatus.success,
        message: 'Sale complete: ${queue.length} item(s), ₦${total.toStringAsFixed(2)}',
      );
      return true;
    } on ScannerFailure catch (e) {
      state = state.copyWith(status: ScannerStatus.error, message: e.message);
      return false;
    } on Failure catch (e) {
      state = state.copyWith(status: ScannerStatus.error, message: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        status: ScannerStatus.error,
        message: ScannerFailure.saleFailed().message,
      );
      return false;
    }
  }
}
