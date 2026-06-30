import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../controllers/auth_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _shopNameController;
  bool _initialized = false;
  File? _selectedImage;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _shopNameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _shopNameController.dispose();
    super.dispose();
  }

  void _initControllers() {
    if (_initialized) return;
    final user = ref.read(currentUserProvider);
    if (user != null) {
      _nameController.text = user.displayName;
      _emailController.text = user.email;
      _phoneController.text = user.phoneNumber ?? '';
      _shopNameController.text = user.shopName ?? '';
      _initialized = true;
    }
  }

  /// Converts a photoUrl (either a base64 data URI or a network URL)
  /// into an appropriate [ImageProvider].
  ImageProvider _imageProviderFromUrl(String url) {
    if (url.startsWith('data:')) {
      // Extract base64 payload from data URI
      final base64Str = url.split(',').last;
      final bytes = base64Decode(base64Str);
      return MemoryImage(bytes);
    }
    return NetworkImage(url);
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appSurfaceRaised,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.appTextTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('Update Profile Photo',
                  style: AppTypography.h3.copyWith(color: context.appTextPrimary)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: AppColors.primary),
                ),
                title: const Text('Take a Photo'),
                subtitle: Text('Use your camera',
                    style: TextStyle(color: context.appTextTertiary, fontSize: 13)),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              Divider(height: 1, indent: 70, color: context.appTextTertiary.withValues(alpha: 0.15)),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      color: AppColors.primary),
                ),
                title: const Text('Choose from Gallery'),
                subtitle: Text('Pick an existing photo',
                    style: TextStyle(color: context.appTextTertiary, fontSize: 13)),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 60,
    );

    if (picked == null || !mounted) return;

    setState(() {
      _selectedImage = File(picked.path);
      _isUploadingPhoto = true;
    });

    final success = await ref
        .read(authControllerProvider.notifier)
        .updateProfilePhoto(picked.path);

    if (!mounted) return;

    setState(() => _isUploadingPhoto = false);

    context.showAppSnackBar(
      message: success ? 'Profile photo updated!' : 'Failed to upload photo',
      type: success ? AppSnackBarType.success : AppSnackBarType.error,
    );

    if (success) {
      // Force re-fetch user profile from Firestore so the updated
      // photoUrl is reflected everywhere via currentUserProvider.
      ref.invalidate(authStateProvider);
    } else {
      setState(() => _selectedImage = null);
    }
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;

    final success =
        await ref.read(authControllerProvider.notifier).updateUserProfile(
              displayName: _nameController.text.trim(),
              phoneNumber: _phoneController.text.trim(),
              shopName: _shopNameController.text.trim(),
            );

    if (success && mounted) {
      ref.invalidate(authStateProvider);
      context.showAppSnackBar(
        message: 'Profile updated successfully',
        type: AppSnackBarType.success,
      );
    }
  }

  void _onDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: context.appTextSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(authControllerProvider.notifier).signOut();
              context.go('/login');
            },
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _initControllers();
    final user = ref.watch(currentUserProvider);
    final authState = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (_, state) {
      if (state.error != null) {
        context.showAppSnackBar(
          message: state.error!,
          type: AppSnackBarType.error,
        );
        ref.read(authControllerProvider.notifier).clearError();
      }
    });

    final initials = (user?.displayName.isNotEmpty == true
            ? user!.displayName
            : 'U')[0]
        .toUpperCase();

    return Scaffold(
      backgroundColor: context.appSurface,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(Icons.store_rounded,
                color: context.appTextPrimary, size: 24),
          ),
        ),
        title: Text('Edit Profile',
            style: AppTypography.h3.copyWith(color: context.appTextPrimary)),
        centerTitle: false,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert,
                color: context.appTextPrimary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            onSelected: (value) {
              if (value == 'logout') {
                ref.read(authControllerProvider.notifier).signOut();
                context.go('/login');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: AppSizes.xxl),

              // ── Avatar Section ──
              Center(
                child: Column(
                  children: [
                    // Avatar with camera button
                    Stack(
                      children: [
                        // Outer ring
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryLight
                                  .withValues(alpha: 0.4),
                              width: 3,
                            ),
                          ),
                          child: Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_selectedImage != null)
                                  CircleAvatar(
                                    radius: 54,
                                    backgroundImage:
                                        FileImage(_selectedImage!),
                                  )
                                else if (user?.photoUrl != null &&
                                    user!.photoUrl!.isNotEmpty)
                                  CircleAvatar(
                                    radius: 54,
                                    backgroundImage:
                                        _imageProviderFromUrl(user.photoUrl!),
                                  )
                                else
                                  CircleAvatar(
                                    radius: 54,
                                    backgroundColor:
                                        AppColors.primarySurface,
                                    child: Text(
                                      initials,
                                      style: AppTypography.h1.copyWith(
                                        color: AppColors.primary,
                                        fontSize: 40,
                                      ),
                                    ),
                                  ),
                                if (_isUploadingPhoto)
                                  Container(
                                    width: 108,
                                    height: 108,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black.withValues(alpha: 0.4),
                                    ),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: AppColors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // Camera button
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: _isUploadingPhoto ? null : _pickImage,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 18,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.lg),

                    // Name
                    Text(
                      user?.displayName.isNotEmpty == true
                          ? user!.displayName
                          : 'User',
                      style: AppTypography.h2.copyWith(
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),

                    // Role badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius:
                            BorderRadius.circular(AppSizes.radiusFull),
                      ),
                      child: Text(
                        'SHOP OWNER',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.xxxl),

              // ── Form Fields ──
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.screenPaddingH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Full Name
                    _ProfileFieldLabel(label: 'FULL NAME'),
                    const SizedBox(height: AppSizes.sm),
                    AppTextField(
                      controller: _nameController,
                      hint: 'Enter your full name',
                      validator: (v) => Validators.required(v, 'Name'),
                      textInputAction: TextInputAction.next,
                      suffixIcon: Icon(Icons.person_rounded,
                          size: 20, color: context.appTextTertiary),
                    ),
                    const SizedBox(height: AppSizes.xxl),

                    // Email (read-only)
                    _ProfileFieldLabel(label: 'EMAIL ADDRESS'),
                    const SizedBox(height: AppSizes.sm),
                    AppTextField(
                      controller: _emailController,
                      hint: 'Email',
                      readOnly: true,
                      enabled: false,
                      suffixIcon: Icon(Icons.alternate_email,
                          size: 20, color: context.appTextTertiary),
                    ),
                    const SizedBox(height: AppSizes.xxl),

                    // Phone Number
                    _ProfileFieldLabel(label: 'PHONE NUMBER'),
                    const SizedBox(height: AppSizes.sm),
                    AppTextField(
                      controller: _phoneController,
                      hint: '+2348136129622',
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        // Phone is optional — only validate if non-empty
                        if (v == null || v.trim().isEmpty) return null;
                        return Validators.phone(v);
                      },
                      suffixIcon: Icon(Icons.phone_rounded,
                          size: 20, color: context.appTextTertiary),
                    ),
                    const SizedBox(height: AppSizes.xxl),

                    // Shop Name
                    _ProfileFieldLabel(label: 'SHOP NAME'),
                    const SizedBox(height: AppSizes.sm),
                    AppTextField(
                      controller: _shopNameController,
                      hint: 'Your shop name',
                      textInputAction: TextInputAction.done,
                      validator: (v) =>
                          Validators.required(v, 'Shop Name'),
                      suffixIcon: Icon(Icons.store_rounded,
                          size: 20, color: context.appTextTertiary),
                    ),
                    const SizedBox(height: AppSizes.xxl),

                    // ── Appearance ──
                    _ProfileFieldLabel(label: 'APPEARANCE'),
                    const SizedBox(height: AppSizes.sm),
                    Container(
                      decoration: BoxDecoration(
                        color: context.appSurface,
                        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                        border: Border.all(color: context.appCardBorder),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              ref.watch(themeModeProvider) == ThemeMode.dark
                                  ? Icons.dark_mode_rounded
                                  : Icons.light_mode_rounded,
                              color: AppColors.primary, size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Dark Mode', style: AppTypography.bodyMedium),
                                Text(
                                  ref.watch(themeModeProvider) == ThemeMode.dark
                                      ? 'Currently dark'
                                      : 'Currently light',
                                  style: AppTypography.bodySmall
                                      .copyWith(color: context.appTextSecondary),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: ref.watch(themeModeProvider) == ThemeMode.dark,
                            onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
                            activeThumbColor: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.xxl),

                    // ── Save Changes Button ──
                    AppButton(
                      label: 'Save Changes',
                      isLoading: authState.isLoading,
                      onPressed: _onSave,
                      icon: Icons.check_circle,
                      backgroundColor: AppColors.primaryDark,
                    ),
                    const SizedBox(height: AppSizes.xxxl),

                    // ── Delete Account ──
                    Center(
                      child: GestureDetector(
                        onTap: _onDeleteAccount,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(Icons.close,
                                  size: 14, color: AppColors.white),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Delete Account',
                              style: AppTypography.labelLarge.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSizes.huge),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section label styled like the Figma design (uppercase, muted)
class _ProfileFieldLabel extends StatelessWidget {
  final String label;

  const _ProfileFieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.labelSmall.copyWith(
        color: context.appTextSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}
