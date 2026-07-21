import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/firestore_paths.dart';
import '../models/shop_settings_model.dart';

import 'package:cloud_functions/cloud_functions.dart';

/// Repository for shop settings (single document per shop)
class SettingsRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  SettingsRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  /// Get current shop settings
  Future<ShopSettings> getSettings(String shopId) async {
    final doc = await _firestore
        .doc(FirestorePaths.shopSettings(shopId))
        .get();
    if (!doc.exists) {
      return ShopSettings.defaults(updatedBy: '');
    }
    return ShopSettingsModel.fromFirestore(doc).toEntity();
  }

  /// Watch shop settings for real-time updates
  Stream<ShopSettings> watchSettings(String shopId) {
    return _firestore
        .doc(FirestorePaths.shopSettings(shopId))
        .snapshots()
        .map((doc) {
      if (!doc.exists) {
        return ShopSettings.defaults(updatedBy: '');
      }
      return ShopSettingsModel.fromFirestore(doc).toEntity();
    });
  }

  /// Update shop settings via Cloud Function
  Future<void> updateSettings(String shopId, ShopSettings settings) async {
    final model = ShopSettingsModel.fromEntity(settings);
    final callable = _functions.httpsCallable('updateShopSettings');
    await callable.call({
      'shopId': shopId,
      'settings': model.toFirestore(),
    });
  }

  /// Update a single setting field via Cloud Function
  Future<void> updateField(
      String shopId, String field, dynamic value, String userId) async {
    final callable = _functions.httpsCallable('updateShopSettings');
    await callable.call({
      'shopId': shopId,
      'settings': {field: value},
    });
  }

  /// Initialize default settings for a new shop
  Future<void> initializeDefaults(String shopId, String userId) async {
    final doc = await _firestore
        .doc(FirestorePaths.shopSettings(shopId))
        .get();
    if (doc.exists) return; // Don't overwrite existing settings

    final defaults = ShopSettingsModel(
      updatedAt: DateTime.now(),
      updatedBy: userId,
    );
    await _firestore
        .doc(FirestorePaths.shopSettings(shopId))
        .set(defaults.toFirestore());
  }
}
