import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthRepositoryImpl({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  AppUser? _cachedUser;

  @override
  AppUser? get currentUser => _cachedUser;

  @override
  Stream<AppUser?> get authStateChanges {
    return _auth.authStateChanges().asyncMap((firebaseUser) async {
      if (firebaseUser == null) {
        _cachedUser = null;
        return null;
      }
      try {
        final user = await _fetchUserProfile(firebaseUser.uid);
        _cachedUser = user;
        return user;
      } catch (e) {
        // User exists in Auth but not in Firestore yet
        _cachedUser = null;
        return null;
      }
    });
  }

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = await _fetchUserProfile(credential.user!.uid);
      _cachedUser = user;
      return user;
    } catch (e) {
      throw _handleException(e);
    }
  }

  @override
  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
    required String shopName,
    required UserRole role,
  }) async {
    try {
      // ── Step 1: Authenticate — create new or sign in if email exists ──
      late final String uid;
      bool isNewAuthUser = false;

      try {
        final credential = await _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        await credential.user!.updateDisplayName(displayName);
        uid = credential.user!.uid;
        isNewAuthUser = true;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          try {
            final credential = await _auth.signInWithEmailAndPassword(
              email: email.trim(),
              password: password,
            );
            await credential.user!.updateDisplayName(displayName);
            uid = credential.user!.uid;
          } on FirebaseAuthException catch (signInError) {
            if (signInError.code == 'wrong-password' ||
                signInError.code == 'invalid-credential') {
              throw const AuthFailure(
                message: 'An account with this email already exists. '
                    'Sign in instead, or use Forgot Password to reset it.',
                code: 'email-already-in-use',
              );
            }
            throw AuthFailure(
              message: 'Unable to access existing account: '
                  '${signInError.message ?? signInError.code}',
              code: signInError.code,
            );
          }
        } else {
          rethrow;
        }
      }

      // ── Step 2: Security — check shop name ownership ──
      // Shop names are globally unique. If the name is already claimed
      // by a different user, registration is blocked immediately.
      QuerySnapshot<Map<String, dynamic>>? shopNameResult;

      if (shopName.trim().isNotEmpty) {
        shopNameResult = await _firestore
            .collection(FirestorePaths.shops)
            .where('name', isEqualTo: shopName.trim())
            .limit(1)
            .get();

        if (shopNameResult.docs.isNotEmpty) {
          final ownerId =
              shopNameResult.docs.first.data()['ownerId'] as String?;

          if (ownerId != uid) {
            // Another account owns this shop name — block and clean up
            if (isNewAuthUser) {
              try { await _auth.currentUser?.delete(); } catch (_) {}
            }
            throw const AuthFailure(
              message: 'This shop name is already registered by another account. '
                  'Please choose a unique shop name.',
              code: 'shop-name-taken',
            );
          }
          // ownerId == uid: same person adding a second profile — allowed
        }
      }

      final now = DateTime.now();

      // ── Step 3: Check if a Firestore profile already exists ──
      final existingDoc = await _firestore
          .collection(FirestorePaths.users)
          .doc(uid)
          .get();

      if (existingDoc.exists) {
        final existingUser =
            UserModel.fromFirestore(existingDoc).toEntity();

        List<UserProfile> profiles = List.from(existingUser.profiles);
        // Auto-migrate legacy user with empty profiles but having shop details
        if (profiles.isEmpty && existingUser.shopId != null && existingUser.shopId!.isNotEmpty) {
          final legacyProfile = UserProfile(
            profileId: 'profile_legacy_${existingUser.createdAt.millisecondsSinceEpoch}',
            displayName: existingUser.displayName,
            role: existingUser.role,
            shopId: existingUser.shopId,
            shopName: existingUser.shopName,
            createdAt: existingUser.createdAt,
          );
          profiles.add(legacyProfile);
          
          try {
            await _firestore
                .collection(FirestorePaths.users)
                .doc(uid)
                .update({
              'profiles': [legacyProfile.toMap()],
              'updatedAt': Timestamp.fromDate(now),
            });
          } catch (_) {
            // Non-fatal migration failure, continue
          }
        }

        if (profiles.isNotEmpty) {
          // ── Same person, adding a second profile ──
          // Search for a matching profile in their own list case-insensitively
          UserProfile? matchingProfile;
          for (final p in profiles) {
            if (p.shopName?.trim().toLowerCase() == shopName.trim().toLowerCase()) {
              matchingProfile = p;
              break;
            }
          }

          String? linkedShopId;
          String? exactShopName;

          if (matchingProfile != null) {
            linkedShopId = matchingProfile.shopId;
            exactShopName = matchingProfile.shopName;
          } else if (shopNameResult != null && shopNameResult.docs.isNotEmpty) {
            linkedShopId = shopNameResult.docs.first.id;
            exactShopName = shopNameResult.docs.first.data()['name'] as String?;
          }

          if (linkedShopId == null) {
            throw const AuthFailure(
              message: 'Shop not found. Enter the exact shop name used when '
                  'you created your first profile to link your accounts.',
              code: 'shop-not-found',
            );
          }

          // Block duplicate roles on the same shop
          final alreadyHasRole = profiles.any(
            (p) => p.role == role && p.shopId == linkedShopId,
          );
          if (alreadyHasRole) {
            throw AuthFailure(
              message: 'You already have a ${role.displayName} profile '
                  'for "${exactShopName ?? shopName.trim()}". Sign in and switch profiles instead.',
              code: 'duplicate-role',
            );
          }

          final newProfile = UserProfile(
            profileId: 'profile_${now.millisecondsSinceEpoch}',
            displayName: displayName.trim(),
            role: role,
            shopId: linkedShopId,
            shopName: exactShopName ?? shopName.trim(),
            createdAt: now,
          );

          await _firestore
              .collection(FirestorePaths.users)
              .doc(uid)
              .update({
            'profiles': FieldValue.arrayUnion([newProfile.toMap()]),
            'updatedAt': Timestamp.fromDate(now),
          });

          final updatedUser = existingUser.copyWith(
            profiles: [...profiles, newProfile],
          );
          _cachedUser = updatedUser;
          return updatedUser;
        }
      }

      // ── Step 4: Brand-new user — create shop (admin) and first profile ──
      String? shopId;
      final firstProfile = UserProfile(
        profileId: 'profile_${now.millisecondsSinceEpoch}',
        displayName: displayName.trim(),
        role: role,
        shopId: role == UserRole.admin && shopName.trim().isNotEmpty ? null : null, // Will be set below
        shopName: shopName.trim().isNotEmpty ? shopName.trim() : null,
        createdAt: now,
      );

      if (role == UserRole.admin && shopName.trim().isNotEmpty) {
        final shopRef =
            _firestore.collection(FirestorePaths.shops).doc();
        shopId = shopRef.id;
        final batch = _firestore.batch();

        batch.set(shopRef, {
          'name': shopName.trim(),
          'ownerId': uid,
          'currency': 'NGN',
          'currencySymbol': '₦',
          'taxRate': 0.0,
          'memberCount': 1,
          'isActive': true,
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        });

        batch.set(
          _firestore.doc(FirestorePaths.shopSettings(shopRef.id)),
          {
            'lowStockThreshold': 5,
            'currency': 'NGN',
            'currencySymbol': '₦',
            'taxRate': 0.0,
            'enableNotifications': true,
            'enableExpiryAlerts': true,
            'expiryAlertDays': 30,
            'updatedAt': Timestamp.fromDate(now),
            'updatedBy': uid,
          },
        );

        final adminProfile = UserProfile(
          profileId: firstProfile.profileId,
          displayName: firstProfile.displayName,
          role: firstProfile.role,
          shopId: shopId,
          shopName: firstProfile.shopName,
          createdAt: firstProfile.createdAt,
        );

        final userModel = UserModel(
          uid: uid,
          email: email.trim(),
          displayName: displayName.trim(),
          role: role.name,
          shopId: shopId,
          shopName: shopName.trim(),
          isActive: true,
          lastLoginAt: now,
          createdAt: now,
          updatedAt: now,
          profiles: [adminProfile.toMap()],
        );

        batch.set(
          _firestore.collection(FirestorePaths.users).doc(uid),
          userModel.toFirestore(),
        );
        await batch.commit();

        final user = AppUser(
          uid: uid,
          email: email.trim(),
          displayName: displayName.trim(),
          role: role,
          shopId: shopId,
          shopName: shopName.trim(),
          isActive: true,
          lastLoginAt: now,
          createdAt: now,
          updatedAt: now,
          profiles: [adminProfile],
        );
        _cachedUser = user;
        return user;
      } else {
        final userModel = UserModel(
          uid: uid,
          email: email.trim(),
          displayName: displayName.trim(),
          role: role.name,
          shopName: shopName.trim(),
          isActive: true,
          lastLoginAt: now,
          createdAt: now,
          updatedAt: now,
          profiles: [firstProfile.toMap()],
        );

        await _firestore
            .collection(FirestorePaths.users)
            .doc(uid)
            .set(userModel.toFirestore());

        final user = AppUser(
          uid: uid,
          email: email.trim(),
          displayName: displayName.trim(),
          role: role,
          shopId: shopId,
          shopName: shopName.trim(),
          isActive: true,
          lastLoginAt: now,
          createdAt: now,
          updatedAt: now,
          profiles: [firstProfile],
        );
        _cachedUser = user;
        return user;
      }
    } catch (e) {
      throw _handleException(e);
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    _cachedUser = null;
  }

  @override
  Future<void> updateProfile({
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    String? shopName,
    String? fcmToken,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AuthFailure(message: 'Not authenticated');

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (displayName != null) updates['displayName'] = displayName;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    if (phoneNumber != null) updates['phoneNumber'] = phoneNumber;
    if (shopName != null) updates['shopName'] = shopName;
    if (fcmToken != null) updates['fcmToken'] = fcmToken;

    await _firestore
        .collection(FirestorePaths.users)
        .doc(uid)
        .update(updates);

    if (_cachedUser != null) {
      _cachedUser = _cachedUser!.copyWith(
        displayName: displayName ?? _cachedUser!.displayName,
        photoUrl: photoUrl ?? _cachedUser!.photoUrl,
        phoneNumber: phoneNumber ?? _cachedUser!.phoneNumber,
        shopName: shopName ?? _cachedUser!.shopName,
        fcmToken: fcmToken ?? _cachedUser!.fcmToken,
      );
    }
  }

  @override
  Future<String> uploadProfilePhoto(String filePath) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AuthFailure(message: 'Not authenticated');

    try {
      final file = File(filePath);

      if (!await file.exists()) {
        throw const AuthFailure(message: 'Selected image file not found');
      }

      final bytes = await file.readAsBytes();

      // Encode as base64 data URI (image is already compressed
      // to 256x256 @ 60% quality by image_picker)
      final base64Str = base64Encode(bytes);
      final dataUri = 'data:image/jpeg;base64,$base64Str';

      // Store in Firestore via the existing updateProfile method
      await updateProfile(photoUrl: dataUri);

      return dataUri;
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure(message: 'Failed to upload photo: $e');
    }
  }

  @override
  Future<AppUser?> getUserById(String uid) async {
    try {
      return await _fetchUserProfile(uid);
    } catch (_) {
      return null;
    }
  }

  Future<AppUser> _fetchUserProfile(String uid) async {
    final doc = await _firestore
        .collection(FirestorePaths.users)
        .doc(uid)
        .get();

    if (!doc.exists) {
      throw const AuthFailure(message: 'User profile not found');
    }

    final user = UserModel.fromFirestore(doc).toEntity();

    // Auto-migrate legacy user with empty profiles but having shop details
    if (user.profiles.isEmpty && user.shopId != null && user.shopId!.isNotEmpty) {
      final legacyProfile = UserProfile(
        profileId: 'profile_legacy_${user.createdAt.millisecondsSinceEpoch}',
        displayName: user.displayName,
        role: user.role,
        shopId: user.shopId,
        shopName: user.shopName,
        createdAt: user.createdAt,
      );

      final migratedUser = user.copyWith(
        profiles: [legacyProfile],
      );

      // Save migration in Firestore asynchronously
      _firestore.collection(FirestorePaths.users).doc(uid).update({
        'profiles': [legacyProfile.toMap()],
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      }).catchError((_) {});

      return migratedUser;
    }

    return user;
  }

  AuthFailure _handleException(dynamic e) {
    if (e is AuthFailure) {
      return e;
    }
    if (e is FirebaseAuthException) {
      return AuthFailure.fromCode(e.code);
    }
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') {
        return const AuthFailure(
          message: 'Access denied: Insufficient permissions to perform database operation.',
          code: 'permission-denied',
        );
      }
      return AuthFailure(
        message: e.message ?? 'A database error occurred. Please try again.',
        code: e.code,
      );
    }
    return AuthFailure(message: e.toString());
  }
}
