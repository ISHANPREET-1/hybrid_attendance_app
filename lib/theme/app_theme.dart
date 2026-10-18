import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF7F2EF),
      textTheme: ThemeData.light().textTheme,
    );
  }
}

class AppColors {
  // Base Colors
  static const Color background = Color(0xFFF7F2EF);
  static const Color cardSurface = Colors.white;
  static const Color surface = Color(0xFFF5F5F5);
  static const Color textPrimary = Color(0xFF1D2631);
  static const Color textSecondary = Color(0xFF6F767E);
  static const Color textDisabledLight = Color(0xFFBDBDBD);
  static const Color iconColor = Color(0xFF1D2631);

  // Primary/Action Colors
  static const Color primary = Color(0xFF37474F);
  static const Color primaryLight = Color(0xFF62727B);
  static const Color primaryDark = Color(0xFF102027);

  // Status Colors
  static const Color success = Colors.green;
  static const Color successLight = Color(0xFFC8E6C9);
  static const Color error = Color(0xFFE53935);
  static const Color errorLight = Color(0xFFFFCDD2);
  static const Color warning = Colors.orange;

  // UI Helpers
  static const Color dividerLight = Color(0xFFEBEBEB);
  static const Color dividerDark = Color(0xFFD1D1D1);
  static const Color inputFillDark = Color(0xFFF0F0F0);
  static const Color inputFillLight = Color(0xFFFFFFFF);

  // Admin Screen Colors (Light Theme Only)
  static const Color textPrimaryDark = Color(0xFF1D2631);
  static const Color textPrimaryLight = Color(0xFF37474F);
  static const Color textSecondaryDark = Color(0xFF6F767E);
  static const Color textSecondaryLight = Color(0xFF90A4AE);
  static const Color cardDark = Colors.white;
  static const Color cardLight = Colors.white;

  // Common Constants
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color transparent = Colors.transparent;
}

class AppTextStyles {
  static TextStyle headlineSmall(Color c) =>
      TextStyle(fontSize: 20, color: c, fontWeight: FontWeight.bold);
  static TextStyle headlineMedium(Color c) =>
      TextStyle(fontSize: 24, color: c, fontWeight: FontWeight.bold);
  static TextStyle bodyMedium(Color c) => TextStyle(fontSize: 14, color: c);
  static TextStyle bodySmall(Color c) => TextStyle(fontSize: 12, color: c);
  static TextStyle labelLarge(Color c) =>
      TextStyle(fontSize: 16, color: c, fontWeight: FontWeight.bold);
  static TextStyle labelMedium(Color c) =>
      TextStyle(fontSize: 14, color: c, fontWeight: FontWeight.w500);
  static TextStyle labelSmall(Color c) => TextStyle(fontSize: 11, color: c);
  static TextStyle caption(Color c) => TextStyle(fontSize: 10, color: c);
}

class AppDecorations {
  static BoxDecoration card({required bool isDark}) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration roleCardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

extension ThemeContext on BuildContext {
  bool get isDark => false;
  Color get appBackground => AppColors.background;
  Color get appCard => AppColors.cardSurface;
  Color get appSurface => AppColors.surface; // Added
  Color get appTextPrimary => AppColors.textPrimary;
  Color get appTextSecondary => AppColors.textSecondary;
  Color get appDivider => AppColors.dividerLight;
  Color get appPrimary => AppColors.primary;
}
