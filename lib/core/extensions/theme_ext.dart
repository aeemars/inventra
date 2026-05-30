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
