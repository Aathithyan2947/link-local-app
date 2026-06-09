import 'package:flutter/material.dart';

/// Link Local palette, derived from the Figma design.
abstract class AppColors {
  // Brand greens
  static const Color primary = Color(0xFF0E9F6E);
  static const Color primaryDark = Color(0xFF07AD61);
  static const Color primaryTint = Color(0xFF90D3BD);
  static const Color primarySurface = Color(0xFFE8F6F0);

  // Neutrals
  static const Color ink = Color(0xFF111111);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF676767);
  static const Color textMuted = Color(0xFF898982);
  static const Color border = Color(0xFFE2E5E1);
  static const Color divider = Color(0xFFD9D9D9);

  // Surfaces
  static const Color background = Color(0xFFF8FAF7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color field = Color(0xFFF4F6F4);

  // Status
  static const Color error = Color(0xFFE53935);
  static const Color success = Color(0xFF0E9F6E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color accent = Color(0xFF8A38F5);

  // Gradient (onboarding / hero)
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [primaryDark, Color(0xFF34C88A)],
  );
}
