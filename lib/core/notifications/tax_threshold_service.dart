import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/firestore_paths.dart';
import '../constants/tax_policy.dart';
import '../../features/analytics/presentation/controllers/annual_revenue_provider.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../shared/providers/firebase_providers.dart';
import '../../shared/models/notification_model.dart';

class TaxThresholdService {
  TaxThresholdService._();

  static void watch(Ref ref) {
    ref.listen<double>(
      annualRevenueProvider,
      (previous, current) async {
        final shopId = ref.read(currentShopIdProvider);
        if (shopId == null) return;

        final year = DateTime.now().year;

        if (current >= TaxPolicy.smallCompanyTurnoverThreshold) {
          await _tryNotifyThresholdCrossed(ref, shopId, year, current);
        } else if (current >= TaxPolicy.approachingThreshold) {
          // Approaching threshold — no in-app write needed,
          // server-side Cloud Function handles the push.
        }
      },
      fireImmediately: true,
    );
  }

  /// Atomically checks and sets the shop's notified-year flag so that only
  /// one device/session across the whole shop fires the in-app notification,
  /// even if several staff members have the app open simultaneously.
  static Future<bool> _claimNotificationSlot(
    String shopId,
    int year,
    String flagSuffix,
  ) async {
    final firestore = FirebaseFirestore.instance;
    final ref = firestore.doc(FirestorePaths.shopSettings(shopId));
    final fieldName = 'taxThresholdNotified_$flagSuffix';

    return firestore.runTransaction<bool>((txn) async {
      final snapshot = await txn.get(ref);
      final data = snapshot.data();
      final alreadyNotifiedYear = data?[fieldName] as int?;
      if (alreadyNotifiedYear == year) return false; // already sent this year

      txn.set(ref, {fieldName: year}, SetOptions(merge: true));
      return true;
    });
  }

  static Future<void> _tryNotifyThresholdCrossed(
    Ref ref, String shopId, int year, double revenue,
  ) async {
    final claimed = await _claimNotificationSlot(shopId, year, 'exceeded');
    if (!claimed) return;

    // Write to Firestore for in-app notification history.
    // The actual push notification is now handled server-side via
    // the checkTaxThreshold Cloud Function + FCM.
    final userId = ref.read(currentUserProvider)?.uid ?? '';
    final repo = ref.read(notificationRepositoryProvider);
    await repo.createNotification(
      shopId,
      AppNotification(
        id: '',
        type: NotificationType.taxThreshold,
        title: 'Annual Revenue Milestone Reached',
        body: 'Tracked revenue for $year has crossed ₦100,000,000. This may '
            'affect your small-company tax exemption status under the Nigeria '
            'Tax Act 2025. Consider consulting a tax professional about CIT '
            'registration and filing.',
        userId: userId,
        createdAt: DateTime.now(),
      ),
    );
  }
}

/// Activate by watching this provider in app.dart.
final taxThresholdProvider = Provider<void>((ref) {
  TaxThresholdService.watch(ref);
});
