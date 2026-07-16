import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../features/inventory/presentation/controllers/inventory_controller.dart';
import '../../shared/models/notification_model.dart';
import '../../shared/providers/firebase_providers.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';

const _kNotifiedIdsKey = 'notified_low_stock_ids';

class StockAlertService {
  StockAlertService._();

  /// Reads the persisted set of product IDs that have already triggered a notification.
  static Set<String> _loadNotifiedIds() {
    final box   = Hive.box<dynamic>('app_prefs');
    final raw   = box.get(_kNotifiedIdsKey, defaultValue: '[]') as String;
    final list  = (jsonDecode(raw) as List).cast<String>();
    return Set<String>.from(list);
  }

  static Future<void> _saveNotifiedIds(Set<String> ids) async {
    final box = Hive.box<dynamic>('app_prefs');
    await box.put(_kNotifiedIdsKey, jsonEncode(ids.toList()));
  }

  /// Call this once from the Riverpod provider below.
  static void watch(Ref ref) {
    ref.listen<List<dynamic>>(
      lowStockProductsProvider,
      (previous, current) async {
        final notified   = _loadNotifiedIds();
        final currentIds = current.map((p) => p.id as String).toSet();

        // ── Write new in-app notifications to Firestore ──
        for (final product in current) {
          final id = product.id as String;
          if (notified.contains(id)) continue; // already alerted

          // Write to Firestore notifications collection for in-app log
          // (push notification is now handled server-side via Cloud Functions)
          final shopId = ref.read(currentShopIdProvider);
          final userId = ref.read(currentUserProvider)?.uid ?? '';
          if (shopId != null) {
            final repo = ref.read(notificationRepositoryProvider);
            await repo.createNotification(
              shopId,
              AppNotification(
                id: '',
                type: (product.isOutOfStock as bool)
                    ? NotificationType.outOfStock
                    : NotificationType.lowStock,
                title: (product.isOutOfStock as bool)
                    ? 'Out of Stock — ${product.name}'
                    : 'Low Stock — ${product.name}',
                body: (product.isOutOfStock as bool)
                    ? '${product.name} has zero ${product.unit} left.'
                    : 'Only ${product.quantity} ${product.unit} remaining (min ${product.reorderLevel}).',
                userId: userId,
                createdAt: DateTime.now(),
              ),
            );
          }

          notified.add(id);
        }

        // ── Clear tracking for restocked products ──
        final restocked = notified.difference(currentIds);
        for (final id in restocked) {
          notified.remove(id);
        }

        await _saveNotifiedIds(notified);
      },
      fireImmediately: true,
    );
  }
}

/// Activate by watching this provider in app.dart.
/// Using [Provider] (not [FutureProvider]) so it stays alive for the app lifetime.
final stockAlertProvider = Provider<void>((ref) {
  StockAlertService.watch(ref);
});
