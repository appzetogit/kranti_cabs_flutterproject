import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextTheme textTheme(Color primaryColor, Color secondaryColor) {
    final base = GoogleFonts.interTextTheme();
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: primaryColor,
        letterSpacing: -0.5,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: primaryColor,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: primaryColor,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: primaryColor,
        fontSize: 28,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: primaryColor,
        fontSize: 22,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: primaryColor,
        fontSize: 20,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: primaryColor,
        fontSize: 18,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: primaryColor,
        fontSize: 16,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
        color: primaryColor,
        fontSize: 14,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: primaryColor,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: secondaryColor,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: secondaryColor,
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: primaryColor,
        fontSize: 14,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: primaryColor,
        fontSize: 12,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontWeight: FontWeight.w500,
        color: secondaryColor,
        fontSize: 11,
      ),
    );
  }

  static const TextStyle earningsFigure = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 32,
    color: Colors.white,
    letterSpacing: -0.5,
  );

  static const TextStyle price = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 20,
    color: AppColors.primary,
  );
}
