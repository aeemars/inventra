import '../entities/app_user.dart';

/// Auth repository contract for domain layer
abstract class AuthRepository {
  /// Stream of auth state changes
  Stream<AppUser?> get authStateChanges;

  /// Get current user (null if not authenticated)
  AppUser? get currentUser;

  /// Sign in with email and password
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  });

  /// Register a new account
  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
    required String shopName,
  });

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email);

  /// Sign out
  Future<void> signOut();

  /// Update user profile
  Future<void> updateProfile({
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    String? shopName,
    String? fcmToken,
    String? editPin,
    String? editPinRecoveryCode,
  });

  /// Upload a profile photo and return the download URL.
  /// [filePath] is the absolute local path of the image file.
  Future<String> uploadProfilePhoto(String filePath);

  /// Get user by UID
  Future<AppUser?> getUserById(String uid);
}
