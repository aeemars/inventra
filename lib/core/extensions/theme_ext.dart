import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

extension ThemeExt on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // Backgrounds
  Color get appBackground  => isDark ? AppColors.darkBackground  : AppColors.background;
  Color get appSurface     => isDark ? AppColors.darkSurface     : AppColors.surface;
  Color get appSurfaceRaised => isDark ? AppColors.darkSurfaceRaised : AppColors.white;

  // Borders & dividers
  Color get appCardBorder  => isDark ? AppColors.darkCardBorder  : AppColors.cardBorder;
  Color get appDivider     => isDark ? AppColors.darkDivider     : AppColors.divider;
  Color get appInputFill   => isDark ? AppColors.darkInputFill   : AppColors.inputFill;
  Color get appInputBorder => isDark ? AppColors.darkInputBorder : AppColors.inputBorder;

  // Text
  Color get appTextPrimary   => isDark ? AppColors.darkTextPrimary   : AppColors.textPrimary;
  Color get appTextSecondary => isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get appTextTertiary  => isDark ? AppColors.darkTextTertiary  : AppColors.textTertiary;
}

enum AppSnackBarType { success, error, warning, info }

extension SnackBarExt on BuildContext {
  void showAppSnackBar({
    required String message,
    required AppSnackBarType type,
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) {
    final isDark = Theme.of(this).brightness == Brightness.dark;
    
    late final Color bgColor;
    late final Color accentColor;
    late final Color textColor;
    late final IconData icon;

    switch (type) {
      case AppSnackBarType.success:
        bgColor = isDark ? const Color(0xFF0F2618) : const Color(0xFFF0FDF4);
        accentColor = isDark ? const Color(0xFF10B981) : const Color(0xFF059669);
        textColor = isDark ? const Color(0xFFECFDF5) : const Color(0xFF065F46);
        icon = Icons.check_circle_rounded;
        break;
      case AppSnackBarType.error:
        bgColor = isDark ? const Color(0xFF2B1216) : const Color(0xFFFFF1F2);
        accentColor = isDark ? const Color(0xFFF43F5E) : const Color(0xFFE11D48);
        textColor = isDark ? const Color(0xFFFFF1F2) : const Color(0xFF9F1239);
        icon = Icons.error_rounded;
        break;
      case AppSnackBarType.warning:
        bgColor = isDark ? const Color(0xFF281E0B) : const Color(0xFFFFFBEB);
        accentColor = isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
        textColor = isDark ? const Color(0xFFFFFBEB) : const Color(0xFF92400E);
        icon = Icons.warning_rounded;
        break;
      case AppSnackBarType.info:
        bgColor = isDark ? const Color(0xFF0F1E36) : const Color(0xFFEFF6FF);
        accentColor = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
        textColor = isDark ? const Color(0xFFEFF6FF) : const Color(0xFF1E40AF);
        icon = Icons.info_rounded;
        break;
    }

    final messenger = ScaffoldMessenger.of(this);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        elevation: 0,
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        behavior: SnackBarBehavior.floating,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: isDark ? 0.2 : 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null && title.isNotEmpty) ...[
                      Text(
                        title,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        height: 1.25,
                      ),
                    ),
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
