import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../features/auth/data/repositories/shop_repository.dart';
import '../../features/sales/data/repositories/transaction_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/analytics_repository.dart';
import '../repositories/settings_repository.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';

// ── Core Firebase Providers ──

/// Firebase Auth instance provider
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Cloud Firestore instance provider
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

// ── Repository Providers ──

/// Shop repository provider
final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  return ShopRepository(firestore: ref.watch(firestoreProvider));
});

/// Transaction & stock movement repository provider
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository(firestore: ref.watch(firestoreProvider));
});

/// Notification repository provider
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(firestore: ref.watch(firestoreProvider));
});

/// Analytics repository provider
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(firestore: ref.watch(firestoreProvider));
});

/// Settings repository provider
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(firestore: ref.watch(firestoreProvider));
});

final currentShopIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.shopId;
});

