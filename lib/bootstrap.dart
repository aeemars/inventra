import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'core/cache/hive_adapters.dart';
import 'core/notifications/local_notification_service.dart';
import 'firebase_options.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── Firebase ──
  if (defaultTargetPlatform == TargetPlatform.linux) {
    debugPrint('Firebase initialization skipped on Linux.');
  } else {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('⚠️ Firebase init failed: $e');
    }

    // ── App Check ──
    // AndroidPlayIntegrityProvider hangs indefinitely on sideloaded APKs
    // (not installed via Play Store). The 6-second timeout forces it to
    // give up so the rest of the app can continue loading.
    const debugAppCheckToken = String.fromEnvironment(
      'FIREBASE_APP_CHECK_DEBUG_TOKEN',
      defaultValue: '',
    );

    try {
      await FirebaseAppCheck.instance
          .activate(
            providerAndroid: kDebugMode
                ? (debugAppCheckToken.isEmpty
                    ? const AndroidDebugProvider()
                    : AndroidDebugProvider(debugToken: debugAppCheckToken))
                : const AndroidPlayIntegrityProvider(),
          )
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () => debugPrint(
              '⚠️ App Check timed out — APK may be sideloaded or Play Integrity '
              'is unavailable. Continuing without attestation.',
            ),
          );
    } catch (e) {
      debugPrint('⚠️ App Check activation failed (non-fatal): $e');
    }
  }

  // ── Hive ──
  try {
    await Hive.initFlutter().timeout(const Duration(seconds: 5));
    await Hive.openBox<dynamic>('app_prefs')
        .timeout(const Duration(seconds: 5));
    registerHiveAdapters();
  } catch (e) {
    debugPrint('⚠️ Hive init failed: $e');
  }

  // ── Local Notifications ──
  try {
    await LocalNotificationService.initialize()
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('⚠️ Notification init failed (non-fatal): $e');
  }
}
