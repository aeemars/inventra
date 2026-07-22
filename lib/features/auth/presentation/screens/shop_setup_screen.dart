import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/app_logo.dart';
import '../controllers/auth_controller.dart';

/// Required, non-dismissible screen shown whenever a signed-in user
/// has `hasShop == false`. This covers:
/// - New Google Sign-In accounts
/// - Any existing account stuck with shopId == null
class ShopSetupScreen extends ConsumerStatefulWidget {
  const ShopSetupScreen({super.key});

  @override
  ConsumerState<ShopSetupScreen> createState() => _ShopSetupScreenState();
}

class _ShopSetupScreenState extends ConsumerState<ShopSetupScreen> {
  final _shopNameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _shopNameController.dispose();
    super.dispose();
  }

  Future<void> _createShop() async {
    final name = _shopNameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .createAndLinkShop(shopName: name);

      ref.invalidate(authStateProvider);
      try {
        await ref.read(authStateProvider.future).timeout(const Duration(seconds: 3));
      } catch (_) {}

      if (mounted) context.go('/dashboard');
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final message = e is Failure
            ? e.message
            : (e is FirebaseException ? (e.message ?? e.toString()) : e.toString());
        context.showAppSnackBar(
          message: 'Could not set up shop: $message',
          type: AppSnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: isDark
                ? [const Color(0xFF0A1F0B), const Color(0xFF1B5E20)]
                : [AppColors.primaryDark, AppColors.primary],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.only(
                    top: 48, bottom: 32, left: 24, right: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(size: 72),
                    const SizedBox(height: 20),
                    const Text(
                      'One Last Step',
                      style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 26,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Name your shop to finish setting up your account.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.white.withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                ),
              ),
              // Form card
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: context.appSurface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 32),
                            decoration: BoxDecoration(
                              color: context.appDivider,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        AppTextField(
                          label: 'Shop Name',
                          controller: _shopNameController,
                          hint: 'e.g. Champions Supermart',
                          prefixIcon: const Icon(Icons.storefront_outlined,
                              size: 20),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'This is how your shop will appear throughout the app. '
                          'You can change it later in your profile settings.',
                          style: AppTypography.bodySmall.copyWith(
                            color: context.appTextTertiary,
                          ),
                        ),
                        const SizedBox(height: AppSizes.xxl),
                        AppButton(
                          label: 'Continue',
                          isLoading: _isLoading,
                          onPressed: _createShop,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
