import 'package:flutter/material.dart';

class AppTheme {
  // Light palette
  static const Color primary = Color(0xFF1565C0); // Deep blue
  static const Color secondary = Color(0xFFFFA726); // Vibrant orange
  static const Color background = Color(0xFFF5F5F5); // Light grey
  static const Color surface = Colors.white;
  static const Color error = Color(0xFFD32F2F);
  static const Color onPrimary = Colors.white;
  static const Color onSecondary = Colors.black;
  static const Color onBackground = Colors.black87;
  static const Color onSurface = Colors.black87;

  static final ThemeData lightTheme = ThemeData(
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      secondary: secondary,
      background: background,
      surface: surface,
      error: error,
      onError: Colors.white,
      onPrimary: onPrimary,
      onSecondary: onSecondary,
      onBackground: onBackground,
      onSurface: onSurface,
    ),
    useMaterial3: true,
  );

  // Dark palette (auto‑generated complementary)
  static const Color darkPrimary = Color(0xFF90CAF9);
  static const Color darkSecondary = Color(0xFFFFCC80);
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkError = Color(0xFFEF9A9A);
  static const Color darkOnPrimary = Colors.black;
  static const Color darkOnSecondary = Colors.black;
  static const Color darkOnBackground = Colors.white70;
  static const Color darkOnSurface = Colors.white70;

  static final ThemeData darkTheme = ThemeData(
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: darkPrimary,
      secondary: darkSecondary,
      background: darkBackground,
      surface: darkSurface,
      error: darkError,
      onError: Colors.white,
      onPrimary: darkOnPrimary,
      onSecondary: darkOnSecondary,
      onBackground: darkOnBackground,
      onSurface: darkOnSurface,
    ),
    useMaterial3: true,
  );
}
