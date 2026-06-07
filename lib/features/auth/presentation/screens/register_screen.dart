import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/entities/app_user.dart';
import '../controllers/auth_controller.dart';

/// Registration screen matching Figma: "Join ShopManager",
/// 4 account type cards, name/email/phone/password, coral Create Account button
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SingleTickerProviderStateMixin {
  static const _signupRoles = [UserRole.admin, UserRole.sales];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  UserRole _selectedRole = UserRole.admin;

  late final AnimationController _ctrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _shopNameController.dispose();
    _passwordController.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authControllerProvider.notifier).register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
          shopName: _shopNameController.text.trim(),
          role: _selectedRole,
        );

    if (success && mounted) {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen(authControllerProvider, (_, state) {
      if (state.error != null) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.error!),
            backgroundColor: AppColors.error,
          ),
        );
        ref.read(authControllerProvider.notifier).clearError();
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
        child: Stack(
          children: [
            Positioned(
              top: -100,
              right: -80,
              child: Opacity(
                opacity: 0.15,
                child: Container(
                  width: 380,
                  height: 380,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -120,
              left: -60,
              child: Opacity(
                opacity: 0.10,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 14,
              child: GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white.withValues(alpha: 0.30)),
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: AppColors.white, size: 18),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // Header section
                  Padding(
                    padding: const EdgeInsets.only(top: 48, bottom: 28, left: 24, right: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryDark.withValues(alpha: 0.45),
                                blurRadius: 28,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: AppColors.white.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.inventory_2_rounded,
                            color: AppColors.primary,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Create Account',
                          style: TextStyle(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 26,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Get started — it only takes a minute',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.white.withValues(alpha: 0.68),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Form card
                  Expanded(
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
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
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Center(
                                    child: Container(
                                      width: 36,
                                      height: 4,
                                      margin: const EdgeInsets.only(bottom: 24),
                                      decoration: BoxDecoration(
                                        color: context.appDivider,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                  // Account Type Label
                                  Text(
                                    'Account Type',
                                    style: AppTypography.labelLarge.copyWith(
                                      color: context.appTextSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.md),
                                  // Account Type Selector
                                  Row(
                                    children: _signupRoles.map((role) {
                                      final isSelected = _selectedRole == role;
                                      return Expanded(
                                        child: GestureDetector(
                                          onTap: () => setState(() => _selectedRole = role),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            margin: const EdgeInsets.symmetric(horizontal: 4),
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? AppColors.primarySurface
                                                  : context.appInputFill,
                                              borderRadius:
                                                  BorderRadius.circular(AppSizes.radiusMd),
                                              border: Border.all(
                                                color: isSelected
                                                    ? AppColors.primary
                                                    : Colors.transparent,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _roleIcon(role),
                                                  color: isSelected
                                                      ? AppColors.primary
                                                      : context.appTextTertiary,
                                                  size: 24,
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  _signupRoleLabel(role),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                    color: isSelected
                                                        ? AppColors.primary
                                                        : context.appTextSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: AppSizes.xxl),

                                  // Full Name
                                  AppTextField(
                                    label: 'Full Name',
                                    hint: 'Enter your full name',
                                    controller: _nameController,
                                    textInputAction: TextInputAction.next,
                                    validator: (v) => Validators.required(v, 'Name'),
                                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                                  ),
                                  const SizedBox(height: AppSizes.lg),

                                  // Email
                                  AppTextField(
                                    label: 'Email Address',
                                    hint: 'name@example.com',
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    validator: Validators.email,
                                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                                  ),
                                  const SizedBox(height: AppSizes.lg),

                                  // Shop Name
                                  AppTextField(
                                    label: 'Shop Name',
                                    hint: 'Champions Supermart',
                                    controller: _shopNameController,
                                    textInputAction: TextInputAction.next,
                                    validator: (v) => Validators.required(v, 'Shop Name'),
                                    prefixIcon: const Icon(Icons.store_outlined, size: 20),
                                  ),
                                  const SizedBox(height: AppSizes.lg),

                                  // Password
                                  AppTextField(
                                    label: 'Password',
                                    hint: '••••••••',
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    validator: Validators.password,
                                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 20,
                                        color: context.appTextTertiary,
                                      ),
                                      onPressed: () {
                                        setState(() => _obscurePassword = !_obscurePassword);
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.xxxl),

                                  // Create Account Button
                                  AppButton(
                                    label: 'Create Account',
                                    isLoading: authState.isLoading,
                                    onPressed: _onRegister,
                                    backgroundColor: AppColors.primary,
                                  ),
                                  const SizedBox(height: AppSizes.xxl),

                                  // Already Have Account
                                  Center(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Already have an account? ',
                                          style: AppTypography.bodyMedium.copyWith(
                                            color: context.appTextSecondary,
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () => context.pop(),
                                          child: Text(
                                            'Log In',
                                            style: AppTypography.labelLarge.copyWith(
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.xxl),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _roleIcon(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Icons.admin_panel_settings_outlined;
      case UserRole.sales:
        return Icons.point_of_sale_rounded;
      case UserRole.warehouse:
        return Icons.warehouse_outlined;
      case UserRole.manager:
        return Icons.manage_accounts_outlined;
    }
  }

  String _signupRoleLabel(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.sales:
        return 'Operator';
      case UserRole.warehouse:
      case UserRole.manager:
        return role.displayName;
    }
  }
}
