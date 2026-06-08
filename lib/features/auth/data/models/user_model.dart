import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/user_profile.dart';

/// Firestore data model for User
class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? phoneNumber;
  final String? shopId;
  final String role;
  final String? shopName;
  final String? fcmToken;
  final bool isActive;
  final DateTime? lastLoginAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Map<String, dynamic>> profiles;

  const UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.phoneNumber,
    this.shopId,
    required this.role,
    this.shopName,
    this.fcmToken,
    this.isActive = true,
    this.lastLoginAt,
    required this.createdAt,
    required this.updatedAt,
    this.profiles = const [],
  });

  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return UserModel(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
      shopId: data['shopId'] as String?,
      role: data['role'] as String? ?? 'sales',
      shopName: data['shopName'] as String?,
      fcmToken: data['fcmToken'] as String?,
      isActive: data['isActive'] as bool? ?? true,
      lastLoginAt: (data['lastLoginAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      profiles: ((data['profiles'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList()) ??
          [],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'phoneNumber': phoneNumber,
      'shopId': shopId,
      'role': role,
      'shopName': shopName,
      'fcmToken': fcmToken,
      'isActive': isActive,
      'lastLoginAt': lastLoginAt != null ? Timestamp.fromDate(lastLoginAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'profiles': profiles,
    };
  }

  AppUser toEntity() {
    return AppUser(
      uid: uid,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      phoneNumber: phoneNumber,
      shopId: shopId,
      shopName: shopName,
      role: _parseRole(role),
      fcmToken: fcmToken,
      isActive: isActive,
      lastLoginAt: lastLoginAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      profiles: profiles.map(UserProfile.fromMap).toList(),
    );
  }

  static UserRole _parseRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'sales':
        return UserRole.sales;
      case 'warehouse':
        return UserRole.warehouse;
      case 'manager':
        return UserRole.manager;
      default:
        return UserRole.sales;
    }
  }

  static UserModel fromEntity(AppUser user, {String? shopName}) {
    return UserModel(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
      phoneNumber: user.phoneNumber,
      shopId: user.shopId,
      role: user.role.name,
      shopName: shopName ?? user.shopName,
      fcmToken: user.fcmToken,
      isActive: user.isActive,
      lastLoginAt: user.lastLoginAt,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      profiles: user.profiles.map((p) => p.toMap()).toList(),
    );
  }
}
