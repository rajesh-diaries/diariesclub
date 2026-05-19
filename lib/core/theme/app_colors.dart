import 'package:flutter/material.dart';

/// Brand palette — see spec/03_SESSION_FOUNDATION.md §6.
class AppColors {
  AppColors._();

  // Brand
  static const navy = Color(0xFF1E3A7B);
  static const gold = Color(0xFFF5C442);

  // Neutral / surfaces — light theme
  static const lightBackground = Color(0xFFF7FBFF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightTextPrimary = Color(0xFF1A1A2E);
  static const lightTextSecondary = Color(0xFF6B7280);
  static const lightBorder = Color(0xFFE2EBF5);

  // Neutral / surfaces — dark theme
  static const darkBackground = Color(0xFF0F1626);
  static const darkSurface = Color(0xFF1A2238);
  static const darkTextPrimary = Color(0xFFE8EEF7);
  static const darkTextSecondary = Color(0xFFA0AAC0);
  static const darkBorder = Color(0xFF2A334A);

  // Semantic
  static const activeGreen = Color(0xFF5BAD4E);
  static const warningYellow = Color(0xFFF5C442);
  static const xpPurple = Color(0xFF9B6BC8);

  // Hero traits
  static const rafiCoral = Color(0xFFE8524A); // Brave
  static const ellieBlue = Color(0xFF5BC8E8); // Kind
  static const gerryAmber = Color(0xFFF0A830); // Curious
  static const zenaGreen = Color(0xFF7BC74D); // Creative

  // Sub-brands
  static const coffeeBrown = Color(0xFFD4A473);
  static const coffeeBrownDeep = Color(0xFF4E2E1F); // banner/hero use — high contrast on white text
  static const fitGreen = Color(0xFF0D4A2E);

  // Session card states
  static const sessionGreenBorder = Color(0xFF5BAD4E);
  static const sessionYellowBorder = Color(0xFFF5C442);
  static const sessionYellowBg = Color(0xFFFFFBEE);

  // Admin only — never use in customer app
  static const adminRed = Color(0xFFE8524A);
}
