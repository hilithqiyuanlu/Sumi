import 'package:flutter/material.dart';

import '../models/models.dart';

// ---------------------------------------------------------------------------
// Design Tokens — aligned with Sumi Design System
// ---------------------------------------------------------------------------

// Spacing (from design spec)
const double s2 = 2;
const double s4 = 4;
const double s6 = 6;
const double s8 = 8;
const double s10 = 10;
const double s12 = 12;
const double s16 = 16;
const double s20 = 20;
const double s24 = 24;
const double s32 = 32;
const double s48 = 48;

// Border Radius (from design spec)
const double radius2 = 2;
const double radius4 = 4;
const double radius8 = 8;
const double radius10 = 10;
const double radius12 = 12; // panel, seg-control
const double radius16 = 16; // input
const double radius18 = 18; // card
const double radius20 = 20; // card-header, large pill
const double radius22 = 22;
const double radius24 = 24;
const double radiusPill = 999;

// Icon sizes (from design spec)
const double iconSmall = 16;
const double iconMedium = 20;
const double iconLarge = 24;

// Legacy aliases (compat with old token names)
const double radiusPanel = radius12;
const double radiusCard = radius18;
const double radiusCardHeader = radius20;
const double iconSection = iconMedium;

// Button sizes (from design spec)
const double sizeButtonSm = 32;
const double sizeButtonMd = 40;
const double sizeButtonLg = 48;
const double sizeInputHeight = 36;

// ---------------------------------------------------------------------------
// Color Palette — aligned with Sumi Design System
// ---------------------------------------------------------------------------

// Primary (Indigo Blue) — Google-inspired
const Color primary50 = Color(0xFFEEF1FE);
const Color primary100 = Color(0xFFD9E2FC);
const Color primary200 = Color(0xFFB4C5FA);
const Color primary300 = Color(0xFF8298F5);
const Color primary400 = Color(0xFF5E76ED);
const Color primary500 = Color(0xFF4758E0); // @primary — main blue
const Color primary600 = Color(0xFF3740C7);
const Color primary700 = Color(0xFF2E35A3);
const Color primary800 = Color(0xFF292D85);
const Color primary900 = Color(0xFF27296B);

// Accent (Coral)
const Color accent50 = Color(0xFFFDF1EE);
const Color accent100 = Color(0xFFF9DED8);
const Color accent200 = Color(0xFFF3C5BB);
const Color accent300 = Color(0xFFEBA69A);
const Color accent400 = Color(0xFFE48E7F);
const Color accent500 = Color(0xFFDF7D6D); // @primary
const Color accent600 = Color(0xFFD0695A);
const Color accent700 = Color(0xFFB55549);
const Color accent800 = Color(0xFF96473E);
const Color accent900 = Color(0xFF7A3B34);

// Tertiary (Amber)
const Color tertiary50 = Color(0xFFFEF8E8);
const Color tertiary100 = Color(0xFFFDEFCD);
const Color tertiary200 = Color(0xFFFBE1A7);
const Color tertiary300 = Color(0xFFF7CF7C);
const Color tertiary400 = Color(0xFFF3BE59);
const Color tertiary500 = Color(0xFFEFAE3E); // @primary
const Color tertiary600 = Color(0xFFD69A31);
const Color tertiary700 = Color(0xFFB38127);
const Color tertiary800 = Color(0xFF90681F);
const Color tertiary900 = Color(0xFF735318);

// Neutral
const Color neutral50 = Color(0xFFF7F8FA);
const Color neutral100 = Color(0xFFEFF1F4); // Google muted bg
const Color neutral200 = Color(0xFFEBEBEB); // Google border
const Color neutral300 = Color(0xFFD4D7DE);
const Color neutral400 = Color(0xFFA8ADB8);
const Color neutral500 = Color(0xFF7F8D9F); // Google muted-foreground
const Color neutral600 = Color(0xFF666E7B);
const Color neutral700 = Color(0xFF4D5565);
const Color neutral800 = Color(0xFF333942); // Google secondary-foreground
const Color neutral900 = Color(0xFF0E1115); // Google foreground

// Success
const Color success500 = Color(0xFF42B570);
const Color success600 = Color(0xFF359D5D);

// Warning
const Color warning500 = Color(0xFFF1BA30);
const Color warning600 = Color(0xFFDBA228);

// Error
const Color error50 = Color(0xFFFCF3F2);
const Color error100 = Color(0xFFF8E0DC);
const Color error500 = Color(0xFFD95D4F);
const Color error600 = Color(0xFFC94A3D);

// Info
const Color info200 = Color(0xFFC4D7F3);
const Color info500 = Color(0xFF5292D4);
const Color info800 = Color(0xFF2B5694);

// Semantic aliases (light)
const Color paper = Color(0xFFFFFFFF); // pure white, Google background
const Color ink = Color(0xFF0E1115); // Google foreground
const Color line = Color(0xFFEBEBEB); // Google border
const Color textTertiary = Color(0xFF7F8D9F); // Google muted-foreground
const Color textSecondary = Color(0xFFA8ADB8); // cool gray
const Color surfaceChip = Color(0xFFEFF1F4); // Google muted
const Color surfaceAlt = Color(0xFFF7F8FA); // cool gray-50
const Color surfaceMuted = Color(0xFFF7F8FA); // cool gray-50

const Color mint = primary100; // primary-100 — indigo-100 for selections
const Color mintDeep = primary500; // primary-500 — indigo-500
const Color lemon = Color(0xFFC5CAFF); // cool indigo-200
const Color lilac = Color(0xFFDCCBFF); // tag-violet
const Color cherry = Color(0xFFF8B4C8); // tag-peach
const Color sky = Color(0xFFB4D4F8); // tag-blue
const Color peach = Color(0xFFC5D4F0); // cool blue-200
const Color sage = Color(0xFFB4D8E8); // cyan-ish

const Color danger = Color(0xFFD95D4F); // error-500

// Interactive overlays (from spec)
const Color interactiveHover = Color(0x144758E0); // 8% primary (indigo)
const Color interactiveFocus = Color(0x1F4758E0); // 12% primary (indigo)
const Color interactivePress = Color(0x294758E0); // 16% primary (indigo)

// ---------------------------------------------------------------------------
// Shadows (from design spec)
// ---------------------------------------------------------------------------

const List<BoxShadow> shadow1 = [
  BoxShadow(color: Color(0x0F0E1115), offset: Offset(0, 1), blurRadius: 3), // Card
];
const List<BoxShadow> shadow2 = [
  BoxShadow(color: Color(0x0A0E1115), offset: Offset(0, 1), blurRadius: 3), // Card Hover
];
const List<BoxShadow> shadow3 = [
  BoxShadow(color: Color(0x0D0E1115), offset: Offset(0, 2), blurRadius: 6), // Float
];
const List<BoxShadow> shadow4 = [
  BoxShadow(color: Color(0x100E1115), offset: Offset(0, 4), blurRadius: 12), // Modal
];
const List<BoxShadow> shadow5 = [
  BoxShadow(color: Color(0x140E1115), offset: Offset(0, 8), blurRadius: 24), // Overlay
];

// ---------------------------------------------------------------------------
// Project color helpers
// ---------------------------------------------------------------------------

Color projectFillColor(ProjectColor c) {
  return switch (c) {
    ProjectColor.lemon => lemon,
    ProjectColor.mint => mint,
    ProjectColor.lilac => lilac,
    ProjectColor.cherry => cherry,
    ProjectColor.sky => sky,
    ProjectColor.peach => peach,
    ProjectColor.sage => sage,
  };
}

Color projectCardBackground(ProjectColor c) {
  return projectFillColor(c).withValues(alpha: 0.25);
}

Color projectTextColor(ProjectColor c, {bool selected = true}) {
  if (!selected) return neutral800.withValues(alpha: 0.4);
  return switch (c) {
    ProjectColor.lemon => const Color(0xFF3949AB),
    ProjectColor.mint => const Color(0xFF2D7A62),
    ProjectColor.lilac => const Color(0xFF6B4FB5),
    ProjectColor.cherry => const Color(0xFF8B3A4A),
    ProjectColor.sky => const Color(0xFF3A5F8B),
    ProjectColor.peach => const Color(0xFF3A5F8B),
    ProjectColor.sage => const Color(0xFF2D6A7A),
  };
}

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary500,
      primary: primary500,
      onPrimary: Colors.white,
      primaryContainer: primary100,
      onPrimaryContainer: primary900,
      secondary: accent100,
      onSecondary: accent900,
      secondaryContainer: accent50,
      onSecondaryContainer: accent800,
      tertiary: tertiary500,
      onTertiary: Colors.white,
      tertiaryContainer: tertiary100,
      onTertiaryContainer: tertiary900,
      surface: paper,
      surfaceDim: neutral100,
      surfaceContainerLowest: paper,
      surfaceContainerLow: neutral100,
      surfaceContainer: neutral100,
      surfaceContainerHigh: neutral200,
      surfaceContainerHighest: neutral300,
      onSurface: ink,
      onSurfaceVariant: neutral500,
      outline: neutral400,
      outlineVariant: neutral200,
      error: error500,
      onError: Colors.white,
      errorContainer: error100,
      onErrorContainer: neutral900,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: paper,
      fontFamily: null,

      // Card — design spec: radius-card (18), shadow-1, no border
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius18),
        ),
      ),

      // Chip — design spec: radius-pill, no border
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        backgroundColor: surfaceChip,
        labelStyle: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w400),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: s10, vertical: s4),
      ),

      // Input — design spec: filled, radius-sm (8), no visible border by default
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: s16, vertical: s12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius8),
          borderSide: const BorderSide(color: primary300, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textTertiary, fontSize: 14),
      ),

      // Filled button — design spec: primary bg, pill radius
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary500,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
          padding: const EdgeInsets.symmetric(horizontal: s24, vertical: s10),
        ),
      ),

      // Outlined button — design spec: pill radius
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
          side: BorderSide(color: neutral300),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // Text button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary500,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // SnackBar — floating with design spec radius
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius12),
        ),
        backgroundColor: primary800,
      ),

      // Switch — iOS style: white thumb + solid track (Material3 compatible)
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary500;
          }
          return neutral300;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
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
      splashColor: primary500.withValues(alpha: 0.15),
    );
  }
}