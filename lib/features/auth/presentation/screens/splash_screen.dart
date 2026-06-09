import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/notifications/local_notification_service.dart';
import '../controllers/auth_controller.dart';


class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {

  // ── Main entrance animation (runs once, 2400ms) ──
  late AnimationController _main;
  late Animation<double>  _bgFade;
  late Animation<double>  _logoOpacity;
  late Animation<Offset>  _logoSlide;
  late Animation<double>  _logoScale;
  late Animation<double>  _nameOpacity;
  late Animation<Offset>  _nameSlide;
  late Animation<double>  _taglineOpacity;
  late Animation<double>  _dotsOpacity;

  // ── Dot bounce animation (repeats) ──
  late AnimationController _dots;

  @override
  void initState() {
    super.initState();

    // Main controller
    _main = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    );

    _bgFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _main, curve: const Interval(0.0, 0.2, curve: Curves.easeIn)),
    );
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _main, curve: const Interval(0.1, 0.4, curve: Curves.easeOut)),
    );
    _logoSlide = Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero).animate(
      CurvedAnimation(parent: _main, curve: const Interval(0.1, 0.45, curve: Curves.elasticOut)),
    );
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _main, curve: const Interval(0.1, 0.45, curve: Curves.elasticOut)),
    );
    _nameOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _main, curve: const Interval(0.35, 0.55, curve: Curves.easeOut)),
    );
    _nameSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _main, curve: const Interval(0.35, 0.6, curve: Curves.easeOut)),
    );
    _taglineOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _main, curve: const Interval(0.5, 0.68, curve: Curves.easeOut)),
    );
    _dotsOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _main, curve: const Interval(0.65, 0.8, curve: Curves.easeIn)),
    );

    // Dot bounce controller
    _dots = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat();

    _main.forward();
    _initApp();
  }

  Future<void> _initApp() async {
    await LocalNotificationService.requestPermission();
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;

    final authState = ref.read(authStateProvider);
    authState.when(
      data: (user) {
        if (user != null) {
          context.go('/dashboard');
        } else {
          context.go('/login');
        }
      },
      loading: () => Future.delayed(
        const Duration(milliseconds: 800),
        () { if (mounted) context.go('/login'); },
      ),
      error: (_, __) => context.go('/login'),
    );
  }

  @override
  void dispose() {
    _main.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _main,
        builder: (context, _) {
          return Container(
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
                // ── Decorative circles ──
                Positioned(
                  top: -100,
                  right: -80,
                  child: Opacity(
                    opacity: _bgFade.value * 0.18,
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
                    opacity: _bgFade.value * 0.12,
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

                // ── Main content ──
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo
                      FadeTransition(
                        opacity: _logoOpacity,
                        child: SlideTransition(
                          position: _logoSlide,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: const AppLogo(size: 100),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // App name
                      FadeTransition(
                        opacity: _nameOpacity,
                        child: SlideTransition(
                          position: _nameSlide,
                          child: Text(
                             'INVENTRA',
                            style: AppTypography.h1.copyWith(
                              color: AppColors.white,
                              fontSize: 38,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Tagline
                      FadeTransition(
                        opacity: _taglineOpacity,
                        child: Text(
                          'Smart Inventory Manager',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.white.withValues(alpha: 0.65),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 60),

                      // Bouncing dots loader
                      FadeTransition(
                        opacity: _dotsOpacity,
                        child: _BouncingDots(controller: _dots),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Three white dots that bounce in a cascading sequence.
class _BouncingDots extends StatelessWidget {
  final AnimationController controller;
  const _BouncingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot is offset by 1/3 of the period
            final t = (controller.value + i / 3) % 1.0;
            // Sine-based vertical bounce: peaks at t=0.5
            final bounce = (t < 0.5 ? t * 2 : 2 - t * 2);
            final offset = bounce * 10.0; // max 10px up
            return Padding(
              padding: EdgeInsets.only(
                right: i < 2 ? 10 : 0,
                bottom: offset,
              ),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.6 + bounce * 0.4),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
