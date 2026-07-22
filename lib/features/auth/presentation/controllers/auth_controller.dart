import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/notifications/fcm_service.dart';
import '../../../../shared/providers/firebase_providers.dart';

// ── Repository Provider ──
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (Firebase.apps.isEmpty) {
    debugPrint('AuthRepository fallback enabled: Firebase is not initialized.');
    return const _UnavailableAuthRepository(
      message:
          'Authentication is unavailable because Firebase is not initialized. Complete Firebase setup and restart the app.',
    );
  }

  return AuthRepositoryImpl();
});

// ── Auth State ──
final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

// ── Current User ──
final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authStateProvider).value;
});

// ── Auth Controller ──
final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(authRepositoryProvider), ref);
});

@immutable
class AuthState {
  final bool isLoading;
  final String? error;
  final bool isSuccess;
  final String? successMessage;

  const AuthState({
    this.isLoading = false,
    this.error,
    this.isSuccess = false,
    this.successMessage,
  });

  AuthState copyWith({
    bool? isLoading,
    String? error,
    bool? isSuccess,
    String? successMessage,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      successMessage: successMessage,
    );
  }

  static const initial = AuthState();
}

class AuthController extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final Ref ref;

  AuthController(this._repository, this.ref) : super(AuthState.initial);

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null, isSuccess: false);
    try {
      await _repository.signInWithEmail(email: email, password: password);
      state = state.copyWith(isLoading: false, isSuccess: true);
      return true;
    } on AuthFailure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'An unexpected error occurred');
      return false;
    }
  }

  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null, isSuccess: false);
    try {
      await _repository.signInWithGoogle();
      state = state.copyWith(isLoading: false, isSuccess: true);
      return true;
    } on AuthFailure catch (e) {
      if (e.code == 'signin-cancelled') {
        state = state.copyWith(isLoading: false);
        return false;
      }
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'An unexpected error occurred');
      return false;
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    state = state.copyWith(isLoading: true, error: null, isSuccess: false);
    try {
      await _repository.sendPasswordResetEmail(email);
      state = state.copyWith(
        isLoading: false,
        isSuccess: true,
        successMessage: 'Password reset email sent',
      );
      return true;
    } on AuthFailure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'An unexpected error occurred');
      return false;
    }
  }

  Future<void> signOut() async {
    final shopId = ref.read(currentShopIdProvider);
    if (shopId != null) {
      await FcmService.unregister(shopId);
    }
    await _repository.signOut();
    state = AuthState.initial;
  }

  Future<bool> updateProfilePhoto(String filePath) async {
    state = state.copyWith(isLoading: true, error: null, isSuccess: false);
    try {
      await _repository.uploadProfilePhoto(filePath);
      state = state.copyWith(
        isLoading: false,
        isSuccess: true,
        successMessage: 'Profile photo updated',
      );
      return true;
    } on Failure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'An unexpected error occurred. Please try again.',
      );
      return false;
    }
  }

  Future<bool> updateUserProfile({
    String? displayName,
    String? phoneNumber,
    String? shopName,
  }) async {
    state = state.copyWith(isLoading: true, error: null, isSuccess: false);
    try {
      await _repository.updateProfile(
        displayName: displayName,
        phoneNumber: phoneNumber,
        shopName: shopName,
      );
      state = state.copyWith(
        isLoading: false,
        isSuccess: true,
        successMessage: 'Profile updated successfully',
      );
      return true;
    } on Failure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'An unexpected error occurred. Please try again.',
      );
      return false;
    }
  }

  Future<bool> verifyPassword(String password) async {
    state = state.copyWith(isLoading: true, error: null, isSuccess: false);
    try {
      final email = ref.read(currentUserProvider)?.email;
      if (email == null) throw const AuthFailure(message: 'User email not found');

      final fbUser = fb_auth.FirebaseAuth.instance.currentUser;
      if (fbUser == null) {
        throw const AuthFailure(message: 'Firebase user session not found');
      }

      final credential = fb_auth.EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await fbUser.reauthenticateWithCredential(credential);
      state = state.copyWith(isLoading: false, isSuccess: true);
      return true;
    } on fb_auth.FirebaseAuthException catch (e) {
      state = state.copyWith(
          isLoading: false, error: e.message ?? 'Verification failed');
      return false;
    } catch (e) {
      state =
          state.copyWith(isLoading: false, error: 'Verification failed: $e');
      return false;
    }
  }

  Future<bool> setEditPin(String newPin, {String? currentPin}) async {
    state = state.copyWith(isLoading: true, error: null, isSuccess: false);
    try {
      await _repository.setEditPin(newPin: newPin, currentPin: currentPin);
      state = state.copyWith(
          isLoading: false,
          isSuccess: true,
          successMessage: 'Edit PIN updated');
      return true;
    } on Failure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Failed to save Edit PIN: $e');
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

class _UnavailableAuthRepository implements AuthRepository {
  final String message;

  const _UnavailableAuthRepository({required this.message});

  @override
  Stream<AppUser?> get authStateChanges => Stream.value(null);

  @override
  AppUser? get currentUser => null;

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) {
    throw AuthFailure(message: message, code: 'auth-unavailable');
  }

  @override
  Future<void> sendPasswordResetEmail(String email) {
    throw AuthFailure(message: message, code: 'auth-unavailable');
  }

  @override
  Future<AppUser> signInWithGoogle() {
    throw AuthFailure(message: message, code: 'auth-unavailable');
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updateProfile({
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    String? shopName,
    String? fcmToken,
  }) {
    throw AuthFailure(message: message, code: 'auth-unavailable');
  }

  @override
  Future<void> setEditPin({required String newPin, String? currentPin}) {
    throw AuthFailure(message: message, code: 'auth-unavailable');
  }

  @override
  Future<bool> verifyEditPin(String pin) {
    throw AuthFailure(message: message, code: 'auth-unavailable');
  }

  @override
  Future<String> requestEditPinReset() {
    throw AuthFailure(message: message, code: 'auth-unavailable');
  }

  @override
  Future<void> confirmEditPinReset({required String code, required String newPin}) {
    throw AuthFailure(message: message, code: 'auth-unavailable');
  }

  @override
  Future<String> uploadProfilePhoto(String filePath) {
    throw AuthFailure(message: message, code: 'auth-unavailable');
  }

  @override
  Future<AppUser?> getUserById(String uid) async => null;

  @override
  Future<AppUser> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String shopName,
  }) {
    throw AuthFailure(message: message, code: 'auth-unavailable');
  }

  @override
  Future<AppUser> createAndLinkShop({required String shopName}) {
    throw AuthFailure(message: message, code: 'auth-unavailable');
  }
}
