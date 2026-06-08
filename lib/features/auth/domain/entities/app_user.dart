import 'package:equatable/equatable.dart';
import 'user_profile.dart';

/// Represents the user's role within a shop
enum UserRole {
  admin,
  sales,
  warehouse,
  manager;

  String get displayName {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.sales:
        return 'Sales';
      case UserRole.warehouse:
        return 'Warehouse';
      case UserRole.manager:
        return 'Manager';
    }
  }

  bool get canManageProducts => this == admin || this == manager || this == warehouse;
  bool get canDeleteProducts => this == admin || this == manager;
  bool get canManageStaff => this == admin;
  bool get canViewReports => this == admin || this == manager;
  bool get canSell => true; // All roles can sell
  bool get canManageSettings => this == admin;
}

/// Domain entity for authenticated user
class AppUser extends Equatable {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? phoneNumber;
  final String? shopId;
  final String? shopName;
  final UserRole role;
  final String? fcmToken;
  final bool isActive;
  final DateTime? lastLoginAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<UserProfile> profiles;

  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.phoneNumber,
    this.shopId,
    this.shopName,
    required this.role,
    this.fcmToken,
    this.isActive = true,
    this.lastLoginAt,
    required this.createdAt,
    required this.updatedAt,
    this.profiles = const [],
  });

  bool get hasShop => shopId != null && shopId!.isNotEmpty;

  AppUser copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    String? shopId,
    String? shopName,
    UserRole? role,
    String? fcmToken,
    bool? isActive,
    DateTime? lastLoginAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<UserProfile>? profiles,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      role: role ?? this.role,
      fcmToken: fcmToken ?? this.fcmToken,
      isActive: isActive ?? this.isActive,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      profiles: profiles ?? this.profiles,
    );
  }

  @override
  List<Object?> get props => [
        uid,
        email,
        displayName,
        photoUrl,
        phoneNumber,
        shopId,
        shopName,
        role,
        fcmToken,
        isActive,
        lastLoginAt,
        profiles,
      ];
}
