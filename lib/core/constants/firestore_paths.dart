/// Firestore collection and document path constants
class FirestorePaths {
  FirestorePaths._();

  // ── Top-level Collections ──
  static const String users = 'users';
  static const String shops = 'shops';

  // ── Shop Sub-collections ──
  static String products(String shopId) => 'shops/$shopId/products';
  static String categories(String shopId) => 'shops/$shopId/categories';
  static String transactions(String shopId) => 'shops/$shopId/transactions';
  static String stockMovements(String shopId) => 'shops/$shopId/stock_movements';
  static String scanHistory(String shopId) => 'shops/$shopId/scan_history';
  static String notifications(String shopId) => 'shops/$shopId/notifications';
  static String analyticsSnapshots(String shopId) => 'shops/$shopId/analytics_snapshots';
  static String fcmTokens(String shopId) => 'shops/$shopId/fcmTokens';

  // ── Shop Documents ──
  static String shopSettings(String shopId) => 'shops/$shopId/settings/config';
  static String shop(String shopId) => 'shops/$shopId';
  static String user(String uid) => 'users/$uid';

  // ── Product Documents ──
  static String product(String shopId, String productId) =>
      'shops/$shopId/products/$productId';

  // ── Category Documents ──
  static String category(String shopId, String categoryId) =>
      'shops/$shopId/categories/$categoryId';

  // ── Transaction Documents ──
  static String transaction(String shopId, String transactionId) =>
      'shops/$shopId/transactions/$transactionId';

  // ── Stock Movement Documents ──
  static String stockMovement(String shopId, String movementId) =>
      'shops/$shopId/stock_movements/$movementId';

  // ── Scan History Documents ──
  static String scanHistoryEntry(String shopId, String scanId) =>
      'shops/$shopId/scan_history/$scanId';

  // ── Notification Documents ──
  static String notification(String shopId, String notificationId) =>
      'shops/$shopId/notifications/$notificationId';

  // ── Analytics Snapshot Documents ──
  static String analyticsSnapshot(String shopId, String dateKey) =>
      'shops/$shopId/analytics_snapshots/$dateKey';
}
