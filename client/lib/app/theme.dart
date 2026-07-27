import 'package:flutter/material.dart';

/// Monochrome black + light-gray palette. No brand color — the design
/// relies on weight, contrast, and elevation rather than hue.
class AppPalette {
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF0A0A0A);
  static const blackPure = Color(0xFF000000);
  static const gray900 = Color(0xFF1A1A1A);
  static const gray800 = Color(0xFF2A2A2A);
  static const gray700 = Color(0xFF3F3F3F);
  static const gray500 = Color(0xFF8A8A8A);
  static const gray300 = Color(0xFFC8C8C8);
  static const gray200 = Color(0xFFE2E2E2);
  static const gray100 = Color(0xFFF0F0F0);
  static const gray50 = Color(0xFFF7F7F7);
}

class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppPalette.black,
      onPrimary: AppPalette.white,
      primaryContainer: AppPalette.gray200,
      onPrimaryContainer: AppPalette.black,
      secondary: AppPalette.gray700,
      onSecondary: AppPalette.white,
      secondaryContainer: AppPalette.gray100,
      onSecondaryContainer: AppPalette.black,
      tertiary: AppPalette.gray500,
      onTertiary: AppPalette.white,
      tertiaryContainer: AppPalette.gray100,
      onTertiaryContainer: AppPalette.black,
      error: Color(0xFFB3261E),
      onError: AppPalette.white,
      errorContainer: Color(0xFFF9DEDC),
      onErrorContainer: Color(0xFF410E0B),
      surface: AppPalette.white,
      onSurface: AppPalette.black,
      surfaceContainerLowest: AppPalette.white,
      surfaceContainerLow: AppPalette.gray50,
      surfaceContainer: AppPalette.gray100,
      surfaceContainerHigh: AppPalette.gray200,
      surfaceContainerHighest: AppPalette.gray300,
      onSurfaceVariant: AppPalette.gray700,
      outline: AppPalette.gray500,
      outlineVariant: AppPalette.gray200,
      inverseSurface: AppPalette.black,
      onInverseSurface: AppPalette.white,
      inversePrimary: AppPalette.gray300,
      shadow: AppPalette.black,
      scrim: AppPalette.black,
      surfaceTint: AppPalette.black,
    );
    return _base(scheme);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppPalette.white,
      onPrimary: AppPalette.black,
      primaryContainer: AppPalette.gray700,
      onPrimaryContainer: AppPalette.white,
      secondary: AppPalette.gray300,
      onSecondary: AppPalette.black,
      secondaryContainer: AppPalette.gray800,
      onSecondaryContainer: AppPalette.white,
      tertiary: AppPalette.gray500,
      onTertiary: AppPalette.black,
      tertiaryContainer: AppPalette.gray800,
      onTertiaryContainer: AppPalette.white,
      error: Color(0xFFF2B8B5),
      onError: Color(0xFF601410),
      errorContainer: Color(0xFF8C1D18),
      onErrorContainer: Color(0xFFF9DEDC),
      surface: AppPalette.gray900,
      onSurface: AppPalette.white,
      surfaceContainerLowest: AppPalette.blackPure,
      surfaceContainerLow: AppPalette.gray900,
      surfaceContainer: AppPalette.gray800,
      surfaceContainerHigh: Color(0xFF333333),
      surfaceContainerHighest: Color(0xFF404040),
      onSurfaceVariant: AppPalette.gray300,
      outline: AppPalette.gray700,
      outlineVariant: AppPalette.gray900,
      inverseSurface: AppPalette.white,
      onInverseSurface: AppPalette.black,
      inversePrimary: AppPalette.gray700,
      shadow: AppPalette.blackPure,
      scrim: AppPalette.blackPure,
      surfaceTint: AppPalette.white,
    );
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
    );
  }
}
