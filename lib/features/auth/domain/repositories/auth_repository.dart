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

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email);

  /// Sign in with Google
  Future<AppUser> signInWithGoogle();

  /// Sign out
  Future<void> signOut();

  /// Update user profile
  Future<void> updateProfile({
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    String? shopName,
    String? fcmToken,
  });

  /// Set the Edit PIN (first time or change with current PIN)
  Future<void> setEditPin({required String newPin, String? currentPin});

  /// Verify an entered PIN against server hash
  Future<bool> verifyEditPin(String pin);

  /// Request a 6-digit PIN reset code emailed to the user's account email
  Future<String> requestEditPinReset();

  /// Confirm emailed reset code and set a new PIN
  Future<void> confirmEditPinReset({required String code, required String newPin});

  /// Upload a profile photo and return the download URL.
  /// [filePath] is the absolute local path of the image file.
  Future<String> uploadProfilePhoto(String filePath);

  /// Get user by UID
  Future<AppUser?> getUserById(String uid);

  /// Register a new email/password account, create their shop, and link
  /// the shop's ID onto the user document in one atomic-as-possible flow.
  Future<AppUser> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String shopName,
  });

  /// For an existing signed-in account with no shop yet (shopId == null),
  /// create a shop and link it. Used both for first-time Google Sign-In
  /// users and as a self-repair path for accounts already stuck without one.
  Future<AppUser> createAndLinkShop({required String shopName});
}
