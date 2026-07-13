import 'package:flutter/material.dart';

import '../models/models.dart';

// ---------------------------------------------------------------------------
// Design Tokens
// ---------------------------------------------------------------------------

// Spacing
const double s2 = 2;
const double s4 = 4;
const double s6 = 6;
const double s8 = 8;
const double s10 = 10;
const double s12 = 12;
const double s14 = 14;
const double s16 = 16;
const double s20 = 20;
const double s24 = 24;

// Radius
const double radiusPanel = 12;
const double radiusCard = 18;
const double radiusCardHeader = 20;
const double radiusPill = 999;

// Icon sizes
const double iconSmall = 16;
const double iconSection = 20;

// ---------------------------------------------------------------------------
// Color Palette
// ---------------------------------------------------------------------------

// Primary / accent
const Color mint = Color(0xFFBEEEDC);
const Color mintDeep = Color(0xFF4AAE92);
const Color lemon = Color(0xFFFFE9A8);
const Color lilac = Color(0xFFDCCBFF);

// System todo card backgrounds
const Color lemonLight = Color(0xFFFFF8E1);
const Color mintLight = Color(0xFFE8F5E9);
const Color lilacLight = Color(0xFFF3E5F5);

// Neutral
const Color ink = Color(0xFF233136);
const Color paper = Color(0xFFFFFBF6);
const Color line = Color(0xFFE9E0D8);
const Color textTertiary = Color(0xFF526166);

// ---------------------------------------------------------------------------
// Project color helpers
// ---------------------------------------------------------------------------

Color projectFillColor(ProjectColor c) {
  return switch (c) {
    ProjectColor.lemon => lemon,
    ProjectColor.mint => mint,
    ProjectColor.lilac => lilac,
  };
}

Color projectCardBackground(ProjectColor c) {
  return switch (c) {
    ProjectColor.lemon => lemonLight,
    ProjectColor.mint => mintLight,
    ProjectColor.lilac => lilacLight,
  };
}

Color projectTextColor(ProjectColor c, {bool selected = true}) {
  if (!selected) return Colors.black54;
  return switch (c) {
    ProjectColor.lemon => const Color(0xFF8B6914),
    ProjectColor.mint => const Color(0xFF2D7A62),
    ProjectColor.lilac => const Color(0xFF6B4FB5),
  };
}

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: mint,
      primary: mintDeep,
      surface: paper,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: paper,
      fontFamily: null, // 使用系统默认字体

      // Card
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),

      // Chip
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        backgroundColor: line.withValues(alpha: 0.3),
        labelStyle: const TextStyle(fontSize: 13, color: ink),
        side: BorderSide.none,
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: s16, vertical: s12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPanel),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPanel),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusPanel),
          borderSide: const BorderSide(color: mintDeep, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textTertiary, fontSize: 14),
      ),

      // Filled button
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: mintDeep,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),

      // Outlined button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Navigation bar
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: mint,
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ),

      // Text styles
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          height: 1.35,
          color: ink,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          height: 1.35,
          color: textTertiary,
        ),
      ),

      // Splash
      splashFactory: InkRipple.splashFactory,
      splashColor: mintDeep.withValues(alpha: 0.15),
    );
  }
}

// ProjectColor 定义于 models/models.dart，此处通过 import 使用
