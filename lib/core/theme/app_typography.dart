import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Poppins-based text theme (matches the Figma typography).
abstract class AppTypography {
  static TextTheme textTheme(TextTheme base) {
    final poppins = GoogleFonts.poppinsTextTheme(base);
    return poppins.copyWith(
      displaySmall: poppins.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineMedium: poppins.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineSmall: poppins.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleLarge: poppins.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleMedium: poppins.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: poppins.bodyLarge?.copyWith(color: AppColors.textPrimary),
      bodyMedium: poppins.bodyMedium?.copyWith(color: AppColors.textSecondary),
      bodySmall: poppins.bodySmall?.copyWith(color: AppColors.textMuted),
      labelLarge: poppins.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
