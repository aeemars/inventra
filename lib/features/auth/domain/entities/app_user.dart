import 'package:equatable/equatable.dart';

/// Domain entity for authenticated user
class AppUser extends Equatable {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? phoneNumber;
  final String? shopId;
  final String? shopName;
  final String? fcmToken;
  final bool isActive;
  final DateTime? lastLoginAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? editPin;
  final String? editPinRecoveryCode;

  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.phoneNumber,
    this.shopId,
    this.shopName,
    this.fcmToken,
    this.isActive = true,
    this.lastLoginAt,
    required this.createdAt,
    required this.updatedAt,
    this.editPin,
    this.editPinRecoveryCode,
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
    String? fcmToken,
    bool? isActive,
    DateTime? lastLoginAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? editPin,
    String? editPinRecoveryCode,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      fcmToken: fcmToken ?? this.fcmToken,
      isActive: isActive ?? this.isActive,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      editPin: editPin ?? this.editPin,
      editPinRecoveryCode: editPinRecoveryCode ?? this.editPinRecoveryCode,
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
        fcmToken,
        isActive,
        lastLoginAt,
        editPin,
        editPinRecoveryCode,
      ];
}
