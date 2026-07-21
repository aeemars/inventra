import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/app_user.dart';

/// Firestore data model for User
class UserModel {
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

  const UserModel({
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

  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return UserModel(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
      shopId: data['shopId'] as String?,
      shopName: data['shopName'] as String?,
      fcmToken: data['fcmToken'] as String?,
      isActive: data['isActive'] as bool? ?? true,
      lastLoginAt: (data['lastLoginAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      editPin: data['editPin'] as String?,
      editPinRecoveryCode: data['editPinRecoveryCode'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'phoneNumber': phoneNumber,
      'shopId': shopId,
      'shopName': shopName,
      'fcmToken': fcmToken,
      'isActive': isActive,
      'lastLoginAt': lastLoginAt != null ? Timestamp.fromDate(lastLoginAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
    if (editPin != null) map['editPin'] = editPin;
    if (editPinRecoveryCode != null) map['editPinRecoveryCode'] = editPinRecoveryCode;
    return map;
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
      fcmToken: fcmToken,
      isActive: isActive,
      lastLoginAt: lastLoginAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      editPin: editPin,
      editPinRecoveryCode: editPinRecoveryCode,
    );
  }

  static UserModel fromEntity(AppUser user) {
    return UserModel(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
      phoneNumber: user.phoneNumber,
      shopId: user.shopId,
      shopName: user.shopName,
      fcmToken: user.fcmToken,
      isActive: user.isActive,
      lastLoginAt: user.lastLoginAt,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      editPin: user.editPin,
      editPinRecoveryCode: user.editPinRecoveryCode,
    );
  }
}
