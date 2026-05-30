import 'package:flutter/material.dart';

/// Inventra brand colors — extracted from Figma design
class AppColors {
  AppColors._();

  // ── Primary Green ──
  static const Color primaryDark = Color(0xFF1B5E20);
  static const Color primary = Color(0xFF2E7D32);
  static const Color primaryLight = Color(0xFF4CAF50);
  static const Color primarySurface = Color(0xFFE8F5E9);

  // ── Coral / Accent ──
  static const Color coral = Color(0xFFE85D3A);
  static const Color coralLight = Color(0xFFFF7F50);

  // ── Scanner ──
  static const Color scannerBlue = Color(0xFF2196F3);
  static const Color scannerDark = Color(0xFF1A1A2E);

  // ── Neutrals ──
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFE5E7EB);
  static const Color inputFill = Color(0xFFF3F4F6);
  static const Color inputBorder = Color(0xFFD1D5DB);

  // ── Text ──
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Status ──
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ── Shadows ──
  static const Color shadow = Color(0x1A000000);
  static const Color shadowLight = Color(0x0D000000);

  // ── Chart Colors ──
  static const List<Color> chartColors = [
    Color(0xFF2E7D32),
    Color(0xFF1565C0),
    Color(0xFFF57C00),
    Color(0xFF7B1FA2),
    Color(0xFFC62828),
    Color(0xFF00838F),
  ];

  // ── Dark Mode Neutrals ──
  static const Color darkBackground    = Color(0xFF111318);
  static const Color darkSurface       = Color(0xFF1C1F26);
  static const Color darkSurfaceRaised = Color(0xFF23272F);
  static const Color darkCardBorder    = Color(0xFF2C2F36);
  static const Color darkDivider       = Color(0xFF2C2F36);
  static const Color darkInputFill     = Color(0xFF1C1F26);
  static const Color darkInputBorder   = Color(0xFF383C46);

  // ── Dark Mode Text ──
  static const Color darkTextPrimary   = Color(0xFFF0F2F5);
  static const Color darkTextSecondary = Color(0xFF9AA0AB);
  static const Color darkTextTertiary  = Color(0xFF5C6370);
}
