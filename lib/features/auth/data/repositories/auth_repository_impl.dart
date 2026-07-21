import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/shop.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/shop_model.dart';
import '../models/user_model.dart';
import '../../../../shared/models/shop_settings_model.dart';

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
    return _auth.authStateChanges().asyncExpand((firebaseUser) {
      if (firebaseUser == null) {
        _cachedUser = null;
        return Stream.value(null);
      }
      return _firestore
          .collection(FirestorePaths.users)
          .doc(firebaseUser.uid)
          .snapshots()
          .asyncMap((snapshot) async {
        if (!snapshot.exists) {
          try {
            final user = await _fetchUserProfile(firebaseUser.uid);
            _cachedUser = user;
            return user;
          } catch (_) {
            _cachedUser = null;
            return null;
          }
        }
        try {
          final user = UserModel.fromFirestore(snapshot).toEntity();
          _cachedUser = user;
          return user;
        } catch (_) {
          _cachedUser = null;
          return null;
        }
      });
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
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e) {
      throw _handleException(e);
    }
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthFailure(
          message: 'Google Sign-In was cancelled by the user',
          code: 'signin-cancelled',
        );
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      final User? firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        throw const AuthFailure(
          message: 'Failed to retrieve user details from Google',
        );
      }

      final uid = firebaseUser.uid;
      final now = DateTime.now();

      // Check if Firestore document already exists
      final doc = await _firestore.collection(FirestorePaths.users).doc(uid).get();

      if (doc.exists) {
        // Existing user: update timestamps
        await _firestore.collection(FirestorePaths.users).doc(uid).update({
          'lastLoginAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        });
        final user = await _fetchUserProfile(uid);
        _cachedUser = user;
        return user;
      } else {
        // Brand new user: create Firestore document without shop.
        // Shop creation happens in a required follow-up step —
        // see ShopSetupScreen, gated by AppUser.hasShop in the router.
        final userModel = UserModel(
          uid: uid,
          email: firebaseUser.email ?? '',
          displayName: firebaseUser.displayName ?? 'Google User',
          shopId: null,
          shopName: null,
          photoUrl: firebaseUser.photoURL,
          isActive: true,
          lastLoginAt: now,
          createdAt: now,
          updatedAt: now,
          editPin: null,
          editPinRecoveryCode: null,
        );

        await _firestore
            .collection(FirestorePaths.users)
            .doc(uid)
            .set(userModel.toFirestore());

        _cachedUser = userModel.toEntity();
        return userModel.toEntity();
      }
    } catch (e) {
      throw _handleException(e);
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    _cachedUser = null;
  }

  @override
  Future<void> updateProfile({
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    String? shopName,
    String? fcmToken,
    String? editPin,
    String? editPinRecoveryCode,
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
    if (editPin != null) updates['editPin'] = editPin;
    if (editPinRecoveryCode != null) {
      updates['editPinRecoveryCode'] = editPinRecoveryCode;
    }

    await _firestore
        .collection(FirestorePaths.users)
        .doc(uid)
        .update(updates);

    if (_cachedUser != null) {
      _cachedUser = _cachedUser!.copyWith(
        displayName: displayName,
        photoUrl: photoUrl,
        phoneNumber: phoneNumber,
        shopName: shopName,
        fcmToken: fcmToken,
        editPin: editPin,
        editPinRecoveryCode: editPinRecoveryCode,
      );
    }
  }

  @override
  Future<String> uploadProfilePhoto(String filePath) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw const AuthFailure(message: 'Not authenticated');

      final file = File(filePath);
      if (!await file.exists()) {
        throw const AuthFailure(message: 'Selected image file not found');
      }

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child('$uid.jpg');

      final uploadTask = await storageRef.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final downloadUrl = await uploadTask.ref.getDownloadURL();
      await updateProfile(photoUrl: downloadUrl);

      return downloadUrl;
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

  @override
  Future<AppUser> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String shopName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = credential.user!.uid;
      await credential.user!.updateDisplayName(displayName.trim());
      final now = DateTime.now();

      // Create the shop first
      final shopRef = _firestore.collection(FirestorePaths.shops).doc();
      final shopModel = ShopModel.fromEntity(Shop(
        id: shopRef.id,
        name: shopName.trim(),
        ownerId: uid,
        email: email.trim(),
        createdAt: now,
        updatedAt: now,
      ));
      final settingsModel = ShopSettingsModel(updatedAt: now, updatedBy: uid);

      final batch = _firestore.batch();
      batch.set(shopRef, shopModel.toFirestore());
      batch.set(
        _firestore.doc(FirestorePaths.shopSettings(shopRef.id)),
        settingsModel.toFirestore(),
      );

      // Create the user document WITH the shopId already set
      final userModel = UserModel(
        uid: uid,
        email: email.trim(),
        displayName: displayName.trim(),
        shopId: shopRef.id,
        shopName: shopName.trim(),
        photoUrl: null,
        isActive: true,
        lastLoginAt: now,
        createdAt: now,
        updatedAt: now,
        editPin: null,
        editPinRecoveryCode: null,
      );
      batch.set(
        _firestore.collection(FirestorePaths.users).doc(uid),
        userModel.toFirestore(),
      );

      await batch.commit();

      final user = userModel.toEntity();
      _cachedUser = user;
      return user;
    } catch (e) {
      throw _handleException(e);
    }
  }

  @override
  Future<AppUser> createAndLinkShop({required String shopName}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const AuthFailure(message: 'Not authenticated');
    }
    try {
      final now = DateTime.now();
      final shopRef = _firestore.collection(FirestorePaths.shops).doc();
      final shopModel = ShopModel.fromEntity(Shop(
        id: shopRef.id,
        name: shopName.trim(),
        ownerId: uid,
        email: _auth.currentUser?.email,
        createdAt: now,
        updatedAt: now,
      ));
      final settingsModel = ShopSettingsModel(updatedAt: now, updatedBy: uid);

      final batch = _firestore.batch();
      batch.set(shopRef, shopModel.toFirestore());
      batch.set(
        _firestore.doc(FirestorePaths.shopSettings(shopRef.id)),
        settingsModel.toFirestore(),
      );
      batch.set(
        _firestore.collection(FirestorePaths.users).doc(uid),
        {
          'shopId': shopRef.id,
          'shopName': shopName.trim(),
          'updatedAt': Timestamp.fromDate(now),
        },
        SetOptions(merge: true),
      );
      await batch.commit();

      final user = await _fetchUserProfile(uid);
      _cachedUser = user;
      return user;
    } catch (e) {
      throw _handleException(e);
    }
  }

  Future<AppUser> _fetchUserProfile(String uid) async {
    final doc = await _firestore
        .collection(FirestorePaths.users)
        .doc(uid)
        .get();

    if (!doc.exists) {
      final firebaseUser = _auth.currentUser;
      final now = DateTime.now();
      final userModel = UserModel(
        uid: uid,
        email: firebaseUser?.email ?? '',
        displayName: firebaseUser?.displayName ??
            (firebaseUser?.email != null && firebaseUser!.email!.contains('@')
                ? firebaseUser.email!.split('@').first
                : 'User'),
        shopId: null,
        shopName: null,
        photoUrl: firebaseUser?.photoURL,
        isActive: true,
        lastLoginAt: now,
        createdAt: now,
        updatedAt: now,
        editPin: null,
        editPinRecoveryCode: null,
      );

      await _firestore
          .collection(FirestorePaths.users)
          .doc(uid)
          .set(userModel.toFirestore());

      return userModel.toEntity();
    }

    return UserModel.fromFirestore(doc).toEntity();
  }

  AuthFailure _handleException(dynamic e) {
    if (e is AuthFailure) {
      return e;
    }
    if (e is FirebaseAuthException) {
      if (e.code == 'network-request-failed') {
        return const AuthFailure(
          message: 'Connection failed. Please check your internet connection and try again.',
          code: 'network-error',
        );
      }
      return AuthFailure.fromCode(e.code);
    }
    if (e is FirebaseException) {
      if (e.code == 'network-request-failed') {
        return const AuthFailure(
          message: 'Connection failed. Please check your internet connection and try again.',
          code: 'network-error',
        );
      }
      return AuthFailure(message: e.message ?? e.toString(), code: e.code);
    }
    if (e is PlatformException) {
      if (e.code == 'network_error' || e.message?.contains('ApiException: 7') == true) {
        return const AuthFailure(
          message: 'Connection failed. Please check your internet connection and try again.',
          code: 'network-error',
        );
      }
      return AuthFailure(
        message: e.message ?? 'A platform error occurred during authentication.',
        code: e.code,
      );
    }

    final errMsg = e.toString().toLowerCase();
    if (errMsg.contains('network_error') ||
        errMsg.contains('network-request-failed') ||
        errMsg.contains('apiexception: 7') ||
        errMsg.contains('network-error') ||
        errMsg.contains('connection failed') ||
        errMsg.contains('failed host lookup') ||
        errMsg.contains('socketexception')) {
      return const AuthFailure(
        message: 'Connection failed. Please check your internet connection and try again.',
        code: 'network-error',
      );
    }

    return AuthFailure(message: e.toString());
  }
}
