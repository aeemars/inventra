import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/notifications/fcm_service.dart';
import 'core/notifications/stock_alert_service.dart';
import 'core/notifications/tax_threshold_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/auth/presentation/controllers/auth_controller.dart';
import 'shared/providers/firebase_providers.dart';

class InventraApp extends ConsumerWidget {
  const InventraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(stockAlertProvider); // keeps the low-stock listener alive
    ref.watch(taxThresholdProvider); // keeps the tax threshold listener alive

    // Register FCM token when shop ID becomes available
    ref.listen<String?>(currentShopIdProvider, (previous, shopId) {
      final uid = ref.read(currentUserProvider)?.uid;
      if (shopId != null && uid != null) {
        FcmService.initialize(shopId: shopId, uid: uid);
      }
    });

    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Inventra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
