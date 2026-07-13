import 'dart:ui' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId   = 'inventra_stock_alerts';
  static const _channelName = 'Stock Alerts';
  static const _channelDesc = 'Low stock and out-of-stock alerts for your inventory';

  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings     = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Create Android notification channel
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Request OS notification permission (Android 13+ / iOS).
  static Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Show a low-stock warning notification.
  static Future<void> showLowStockAlert({
    required int id,
    required String productName,
    required int currentQty,
    required int reorderLevel,
    required String unit,
  }) async {
    await _show(
      id: id,
      title: '⚠️ Low Stock — $productName',
      body: 'Only $currentQty $unit remaining (reorder at $reorderLevel $unit).',
    );
  }

  /// Show an out-of-stock critical notification.
  static Future<void> showOutOfStockAlert({
    required int id,
    required String productName,
    required String unit,
  }) async {
    await _show(
      id: id,
      title: '🚨 Out of Stock — $productName',
      body: '$productName has zero $unit left. Restock immediately.',
    );
  }

  static Future<void> showTaxThresholdAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    await _show(id: id, title: title, body: body);
  }

  /// Cancel a notification by id (call when stock is replenished).
  static Future<void> cancel(int id) => _plugin.cancel(id);

  static Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await initialize();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          color: Color(0xFF2E7D32),
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
