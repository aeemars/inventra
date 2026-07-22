import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../domain/entities/shop.dart';
import '../models/shop_model.dart';
import '../../../../shared/models/shop_settings_model.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Repository for shop-level operations
class ShopRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  ShopRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  /// Create a new shop and initialize its owner membership document via Cloud Function.
  /// Returns the created Shop with its generated ID.
  Future<Shop> createShop({
    required String name,
    required String ownerId,
    String? email,
  }) async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final callable = _functions.httpsCallable('createShopAndOwner');
    final response = await callable.call({
      'name': name,
    });

    final resData = Map<String, dynamic>.from(response.data as Map);
    final shopId = resData['shopId'] as String;
    final now = DateTime.now();

    return Shop(
      id: shopId,
      name: name,
      ownerId: ownerId,
      email: email,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Get a shop by ID
  Future<Shop?> getShop(String shopId) async {
    final doc = await _firestore
        .collection(FirestorePaths.shops)
        .doc(shopId)
        .get();
    if (!doc.exists) return null;
    return ShopModel.fromFirestore(doc).toEntity();
  }

  /// Watch a shop document for real-time updates
  Stream<Shop?> watchShop(String shopId) {
    return _firestore
        .collection(FirestorePaths.shops)
        .doc(shopId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return ShopModel.fromFirestore(doc).toEntity();
    });
  }

  /// Update shop profile fields
  Future<void> updateShop(String shopId, Map<String, dynamic> updates) async {
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _firestore
        .collection(FirestorePaths.shops)
        .doc(shopId)
        .update(updates);
  }

  /// Get shop settings
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

  /// Update shop settings
  Future<void> updateSettings(String shopId, ShopSettings settings) async {
    final model = ShopSettingsModel.fromEntity(settings);
    await _firestore
        .doc(FirestorePaths.shopSettings(shopId))
        .set(model.toFirestore(), SetOptions(merge: true));
  }
}
