import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Domain entity for shop configuration settings
class ShopSettings extends Equatable {
  final int lowStockThreshold;
  final String currency;
  final String currencySymbol;
  final double taxRate;
  final String? receiptFooter;
  final bool enableNotifications;
  final bool enableExpiryAlerts;
  final int expiryAlertDays;
  final DateTime updatedAt;
  final String updatedBy;
  final int? taxThresholdNotifiedYear;

  const ShopSettings({
    this.lowStockThreshold = 5,
    this.currency = 'NGN',
    this.currencySymbol = '₦',
    this.taxRate = 0.0,
    this.receiptFooter,
    this.enableNotifications = true,
    this.enableExpiryAlerts = true,
    this.expiryAlertDays = 30,
    required this.updatedAt,
    required this.updatedBy,
    this.taxThresholdNotifiedYear,
  });

  /// Default settings for a newly created shop
  factory ShopSettings.defaults({required String updatedBy}) {
    return ShopSettings(
      updatedAt: DateTime.now(),
      updatedBy: updatedBy,
    );
  }

  ShopSettings copyWith({
    int? lowStockThreshold,
    String? currency,
    String? currencySymbol,
    double? taxRate,
    String? receiptFooter,
    bool? enableNotifications,
    bool? enableExpiryAlerts,
    int? expiryAlertDays,
    DateTime? updatedAt,
    String? updatedBy,
    int? taxThresholdNotifiedYear,
  }) {
    return ShopSettings(
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      currency: currency ?? this.currency,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      taxRate: taxRate ?? this.taxRate,
      receiptFooter: receiptFooter ?? this.receiptFooter,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      enableExpiryAlerts: enableExpiryAlerts ?? this.enableExpiryAlerts,
      expiryAlertDays: expiryAlertDays ?? this.expiryAlertDays,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      taxThresholdNotifiedYear: taxThresholdNotifiedYear ?? this.taxThresholdNotifiedYear,
    );
  }

  @override
  List<Object?> get props => [
        lowStockThreshold,
        currency,
        taxRate,
        enableNotifications,
        enableExpiryAlerts,
        taxThresholdNotifiedYear,
      ];
}

/// Firestore data model for ShopSettings
class ShopSettingsModel {
  final int lowStockThreshold;
  final String currency;
  final String currencySymbol;
  final double taxRate;
  final String? receiptFooter;
  final bool enableNotifications;
  final bool enableExpiryAlerts;
  final int expiryAlertDays;
  final DateTime updatedAt;
  final String updatedBy;
  final int? taxThresholdNotifiedYear;

  const ShopSettingsModel({
    this.lowStockThreshold = 5,
    this.currency = 'NGN',
    this.currencySymbol = '₦',
    this.taxRate = 0.0,
    this.receiptFooter,
    this.enableNotifications = true,
    this.enableExpiryAlerts = true,
    this.expiryAlertDays = 30,
    required this.updatedAt,
    required this.updatedBy,
    this.taxThresholdNotifiedYear,
  });

  factory ShopSettingsModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return ShopSettingsModel(
      lowStockThreshold: (d['lowStockThreshold'] as num?)?.toInt() ?? 5,
      currency: d['currency'] as String? ?? 'NGN',
      currencySymbol: d['currencySymbol'] as String? ?? '₦',
      taxRate: (d['taxRate'] as num?)?.toDouble() ?? 0.0,
      receiptFooter: d['receiptFooter'] as String?,
      enableNotifications: d['enableNotifications'] as bool? ?? true,
      enableExpiryAlerts: d['enableExpiryAlerts'] as bool? ?? true,
      expiryAlertDays: (d['expiryAlertDays'] as num?)?.toInt() ?? 30,
      updatedAt:
          (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedBy: d['updatedBy'] as String? ?? '',
      taxThresholdNotifiedYear: (d['taxThresholdNotifiedYear'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'lowStockThreshold': lowStockThreshold,
      'currency': currency,
      'currencySymbol': currencySymbol,
      'taxRate': taxRate,
      'receiptFooter': receiptFooter,
      'enableNotifications': enableNotifications,
      'enableExpiryAlerts': enableExpiryAlerts,
      'expiryAlertDays': expiryAlertDays,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
      'taxThresholdNotifiedYear': taxThresholdNotifiedYear,
    };
  }

  ShopSettings toEntity() {
    return ShopSettings(
      lowStockThreshold: lowStockThreshold,
      currency: currency,
      currencySymbol: currencySymbol,
      taxRate: taxRate,
      receiptFooter: receiptFooter,
      enableNotifications: enableNotifications,
      enableExpiryAlerts: enableExpiryAlerts,
      expiryAlertDays: expiryAlertDays,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
      taxThresholdNotifiedYear: taxThresholdNotifiedYear,
    );
  }

  static ShopSettingsModel fromEntity(ShopSettings settings) {
    return ShopSettingsModel(
      lowStockThreshold: settings.lowStockThreshold,
      currency: settings.currency,
      currencySymbol: settings.currencySymbol,
      taxRate: settings.taxRate,
      receiptFooter: settings.receiptFooter,
      enableNotifications: settings.enableNotifications,
      enableExpiryAlerts: settings.enableExpiryAlerts,
      expiryAlertDays: settings.expiryAlertDays,
      updatedAt: settings.updatedAt,
      updatedBy: settings.updatedBy,
      taxThresholdNotifiedYear: settings.taxThresholdNotifiedYear,
    );
  }
}
