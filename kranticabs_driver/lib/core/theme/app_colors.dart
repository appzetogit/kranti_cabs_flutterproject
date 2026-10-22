import 'package:flutter/material.dart';

/// Single source of truth for the driver app's visual color tokens.
/// Strictly enforces the Pure Dark Theme matching the user app.
class AppColors {
  AppColors._();

  // Brand Highlights & Accents (Black & Gold, same as user app)
  static const Color primary = Color(0xFFF5B400);
  static const Color primaryDark = Color(0xFFF5B400);
  static const Color primaryLight = Color(0xFFFFF4CC);
  static const Color accent = Color(0xFFF5B400);
  static const Color accentDark = Color(0xFF0F172A);

  // Driver status
  static const Color online = Color(0xFFF5B400);
  static const Color offline = Color(0xFF64748B);
  static const Color onRide = Color(0xFFF59E0B);
  static const Color sos = Color(0xFFEF4444);

  // Semantic
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Single Theme Surfaces & Text (Matching User App Pure Dark Theme)
  static const Color lightBackground = Color(0xFF11191D);
  static const Color lightSurface = Color(0xFF222222);
  static const Color lightCard = Color(0xFF222222);
  static const Color lightBorder = Color(0xFF2E2E2E);
  static const Color lightTextPrimary = Color(0xFFFFFFFF);
  static const Color lightTextSecondary = Color(0xFF94A3B8);

  static const Color darkBackground = Color(0xFF11191D);
  static const Color darkSurface = Color(0xFF222222);
  static const Color darkCard = Color(0xFF222222);
  static const Color darkBorder = Color(0xFF2E2E2E);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  // Gradients
  static const List<Color> primaryGradient = [
    Color(0xFFF5B400),
    Color(0xFFF5B400),
  ];

  static const List<Color> accentGradient = [
    Color(0xFF0F172A),
    Color(0xFFF5B400),
  ];

  static const List<Color> onlineGradient = [
    Color(0xFFF5B400),
    Color(0xFFF5B400),
  ];

  static const List<Color> earningsGradient = [
    Color(0xFF0F172A),
    Color(0xFF222222),
  ];

  static const List<Color> mapPulseGradient = [
    Color(0x33F5B400),
    Color(0x00F5B400),
  ];
}
