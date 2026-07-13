import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Notification type enumeration
enum NotificationType {
  lowStock,
  outOfStock,
  expiryWarning,
  system,
  taxThreshold;

  String get firestoreValue {
    switch (this) {
      case NotificationType.lowStock:
        return 'low_stock';
      case NotificationType.outOfStock:
        return 'out_of_stock';
      case NotificationType.expiryWarning:
        return 'expiry_warning';
      case NotificationType.system:
        return 'system';
      case NotificationType.taxThreshold:
        return 'tax_threshold';
    }
  }

  static NotificationType fromString(String? value) {
    switch (value) {
      case 'low_stock':
        return NotificationType.lowStock;
      case 'out_of_stock':
        return NotificationType.outOfStock;
      case 'expiry_warning':
        return NotificationType.expiryWarning;
      case 'system':
        return NotificationType.system;
      case 'tax_threshold':
        return NotificationType.taxThreshold;
      default:
        return NotificationType.system;
    }
  }
}

/// Domain entity for a notification
class AppNotification extends Equatable {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final bool read;
  final String? userId;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data,
    this.read = false,
    this.userId,
    required this.createdAt,
  });

  AppNotification copyWith({
    String? id,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    bool? read,
    String? userId,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      read: read ?? this.read,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, type, title, read, createdAt];
}

/// Firestore data model for Notification
class NotificationModel {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final bool read;
  final String? userId;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data,
    this.read = false,
    this.userId,
    required this.createdAt,
  });

  factory NotificationModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return NotificationModel(
      id: doc.id,
      type: d['type'] as String? ?? 'system',
      title: d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      data: d['data'] as Map<String, dynamic>?,
      read: d['read'] as bool? ?? false,
      userId: d['userId'] as String?,
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'title': title,
      'body': body,
      'data': data,
      'read': read,
      'userId': userId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  AppNotification toEntity() {
    return AppNotification(
      id: id,
      type: NotificationType.fromString(type),
      title: title,
      body: body,
      data: data,
      read: read,
      userId: userId,
      createdAt: createdAt,
    );
  }

  static NotificationModel fromEntity(AppNotification notification) {
    return NotificationModel(
      id: notification.id,
      type: notification.type.firestoreValue,
      title: notification.title,
      body: notification.body,
      data: notification.data,
      read: notification.read,
      userId: notification.userId,
      createdAt: notification.createdAt,
    );
  }
}
