import 'package:equatable/equatable.dart';
import 'app_user.dart';

class UserProfile extends Equatable {
  final String profileId;
  final String displayName;
  final UserRole role;
  final String? shopId;
  final String? shopName;
  final DateTime createdAt;

  const UserProfile({
    required this.profileId,
    required this.displayName,
    required this.role,
    this.shopId,
    this.shopName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'profileId': profileId,
    'displayName': displayName,
    'role': role.name,
    'shopId': shopId,
    'shopName': shopName,
    'createdAt': createdAt.toIso8601String(),
  };

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
    profileId: map['profileId'] as String? ?? '',
    displayName: map['displayName'] as String? ?? '',
    role: UserRole.values.firstWhere(
      (e) => e.name == (map['role'] as String? ?? 'sales'),
      orElse: () => UserRole.sales,
    ),
    shopId: map['shopId'] as String?,
    shopName: map['shopName'] as String?,
    createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  @override
  List<Object?> get props => [profileId, role, shopId];
}
