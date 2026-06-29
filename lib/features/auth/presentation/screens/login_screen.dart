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
import '../../../../core/widgets/app_logo.dart';
import '../controllers/auth_controller.dart';

/// Login screen matching Figma: green shield logo, "Welcome Back",
/// email/password fields, green Sign In button, Create Account link
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

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
    _emailController.dispose();
    _passwordController.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onSignIn() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authControllerProvider.notifier).signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
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
            SafeArea(
              child: Column(
                children: [
                  // Header section
                  Padding(
                    padding: const EdgeInsets.only(
                        top: 32, bottom: 28, left: 24, right: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppLogo(size: 80),
                        const SizedBox(height: 14),
                        const Text(
                          'Welcome Back',
                          style: TextStyle(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 26,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sign in to manage your inventory',
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
                                crossAxisAlignment: CrossAxisAlignment.center,
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
                                  // ── Email Field ──
                                  AppTextField(
                                    label: 'Email Address',
                                    hint: 'name@example.com',
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    validator: Validators.email,
                                    prefixIcon: const Icon(Icons.email_outlined,
                                        size: 20),
                                  ),
                                  const SizedBox(height: AppSizes.lg),

                                  // ── Password Field ──
                                  AppTextField(
                                    label: 'Password',
                                    hint: '••••••••',
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    validator: Validators.password,
                                    prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                        size: 20),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 20,
                                        color: context.appTextTertiary,
                                      ),
                                      onPressed: () {
                                        setState(() => _obscurePassword =
                                            !_obscurePassword);
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.sm),

                                  // ── Forgot Password ──
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () =>
                                          context.push('/forgot-password'),
                                      child: const Text('Forgot Password?'),
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.xxl),

                                  // ── Sign In Button ──
                                  AppButton(
                                    label: 'Sign In',
                                    isLoading: authState.isLoading,
                                    onPressed: _onSignIn,
                                  ),
                                  const SizedBox(height: AppSizes.xxl),

                                  // ── Divider ──
                                  Row(
                                    children: [
                                      const Expanded(child: Divider()),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16),
                                        child: Text(
                                          'Or continue with',
                                          style:
                                              AppTypography.bodySmall.copyWith(
                                            color: context.appTextTertiary,
                                          ),
                                        ),
                                      ),
                                      const Expanded(child: Divider()),
                                    ],
                                  ),
                                  const SizedBox(height: AppSizes.xl),

                                  // ── Social Login ──
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _socialButton(
                                          Icons.g_mobiledata_rounded, 'Google'),
                                      const SizedBox(width: AppSizes.lg),
                                      _socialButton(
                                          Icons.apple_rounded, 'Apple'),
                                    ],
                                  ),
                                  const SizedBox(height: AppSizes.huge),

                                  // ── Create Account ──
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "Don't have an account? ",
                                        style:
                                            AppTypography.bodyMedium.copyWith(
                                          color: context.appTextSecondary,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => context.push('/register'),
                                        child: Text(
                                          'Create Account',
                                          style:
                                              AppTypography.labelLarge.copyWith(
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSizes.xxl),

                                  // ── Footer ──
                                  Text(
                                    'Built by aeem',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: context.appTextTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.xl),
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

  Widget _socialButton(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: context.appCardBorder),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Icon(icon, size: 28, color: context.appTextSecondary),
    );
  }
}
