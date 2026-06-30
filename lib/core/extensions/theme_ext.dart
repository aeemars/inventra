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
    Duration duration = const Duration(seconds: 4),
  }) {
    final isDark = Theme.of(this).brightness == Brightness.dark;
    
    late final Color bgColor;
    late final Color borderColor;
    late final Color textColor;
    late final Color iconColor;
    late final IconData icon;

    switch (type) {
      case AppSnackBarType.success:
        bgColor = isDark ? const Color(0xFF1B4323) : const Color(0xFFE8F5E9);
        borderColor = isDark ? const Color(0xFF2E7D32) : const Color(0xFFA5D6A7);
        textColor = isDark ? const Color(0xFFE8F5E9) : const Color(0xFF1B5E20);
        iconColor = isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
        icon = Icons.check_circle_rounded;
        break;
      case AppSnackBarType.error:
        bgColor = isDark ? const Color(0xFF4C1D1D) : const Color(0xFFFFEBEE);
        borderColor = isDark ? const Color(0xFFB71C1C) : const Color(0xFFFFCDD2);
        textColor = isDark ? const Color(0xFFFFEBEE) : const Color(0xFFC62828);
        iconColor = isDark ? const Color(0xFFEF9A9A) : const Color(0xFFD32F2F);
        icon = Icons.error_outline_rounded;
        break;
      case AppSnackBarType.warning:
        bgColor = isDark ? const Color(0xFF4A3B12) : const Color(0xFFFFF3E0);
        borderColor = isDark ? const Color(0xFFF59E0B) : const Color(0xFFFFE0B2);
        textColor = isDark ? const Color(0xFFFFF3E0) : const Color(0xFFE65100);
        iconColor = isDark ? const Color(0xFFFFCC80) : const Color(0xFFF57C00);
        icon = Icons.warning_amber_rounded;
        break;
      case AppSnackBarType.info:
        bgColor = isDark ? const Color(0xFF0D2C54) : const Color(0xFFE3F2FD);
        borderColor = isDark ? const Color(0xFF1976D2) : const Color(0xFFBBDEFB);
        textColor = isDark ? const Color(0xFFE3F2FD) : const Color(0xFF0D47A1);
        iconColor = isDark ? const Color(0xFF90CAF9) : const Color(0xFF1976D2);
        icon = Icons.info_outline_rounded;
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: isDark ? const Color(0x33000000) : const Color(0x1A000000),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
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
