import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'core/cache/hive_adapters.dart';
import 'core/notifications/local_notification_service.dart';
import 'firebase_options.dart';

/// Initialize Firebase, Hive, and system UI
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Firebase
  if (defaultTargetPlatform == TargetPlatform.linux) {
    debugPrint(
      'Firebase initialization is skipped on Linux desktop for this setup. '
      'Use a supported target (Android/iOS/Web/macOS/Windows) or add Linux-specific Firebase support if needed.',
    );
  } else {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    const debugAppCheckToken = String.fromEnvironment(
      'FIREBASE_APP_CHECK_DEBUG_TOKEN',
      defaultValue: '',
    );

    // App Check must be active before auth/database calls.
    // Wrapped in try-catch: Play Integrity will fail for sideloaded APKs
    // that are not distributed via Google Play Store.
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? (debugAppCheckToken.isEmpty
                ? const AndroidDebugProvider()
                : const AndroidDebugProvider(debugToken: debugAppCheckToken))
            : const AndroidPlayIntegrityProvider(),
      );
    } catch (e) {
      debugPrint('⚠️ App Check activation failed (non-fatal): $e');
    }
  }

  // Hive (local storage)
  await Hive.initFlutter();
  await Hive.openBox<dynamic>('app_prefs');
  registerHiveAdapters();

  try {
    await LocalNotificationService.initialize()
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('⚠️ Notification init failed (non-fatal): $e');
  }
}
