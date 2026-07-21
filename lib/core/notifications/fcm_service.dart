import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../constants/firestore_paths.dart';
import 'local_notification_service.dart';

/// Must be a top-level function — required by firebase_messaging for
/// handling messages that arrive while the app is fully terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No UI work here — Android/iOS auto-display the notification payload
  // when the app is backgrounded or terminated. This handler exists only
  // so data-only messages can still be processed if needed later.
  debugPrint('Background FCM message: ${message.messageId}');
}

class FcmService {
  FcmService._();

  static Future<void> initialize({
    required String shopId,
    required String uid,
  }) async {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('FCM permission denied');
      return;
    }

    await _registerToken(shopId, uid);

    // Re-register whenever the token rotates (happens periodically)
    messaging.onTokenRefresh.listen((newToken) {
      _saveToken(shopId, uid, newToken);
    });

    // Foreground messages: Android/iOS do NOT auto-display a notification
    // while the app is open, so we render it ourselves via the existing
    // local notification channel.
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title;
      final body = message.notification?.body;
      if (title == null || body == null) return;

      LocalNotificationService.showTaxThresholdAlert(
        id: message.hashCode,
        title: title,
        body: body,
      );
    });
  }

  static Future<void> _registerToken(String shopId, String uid) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await _saveToken(shopId, uid, token);
  }

  static Future<void> _saveToken(
      String shopId, String uid, String token) async {
    final platformName = defaultTargetPlatform.name.toLowerCase();
    final cleanPlatform = ['ios', 'android', 'web'].contains(platformName)
        ? platformName
        : 'web';

    await FirebaseFirestore.instance
        .collection(FirestorePaths.fcmTokens(shopId))
        .doc(token)
        .set({
      'uid': uid,
      'token': token,
      'platform': cleanPlatform,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Call on sign-out so a stale token isn't left registered to a shop
  /// the user no longer has access to.
  static Future<void> unregister(String shopId) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await FirebaseFirestore.instance
        .collection(FirestorePaths.fcmTokens(shopId))
        .doc(token)
        .delete();
  }
}
