import 'package:flutter/material.dart';

/// Black / white / dark-maroon palette.
///
/// Light mode: white surface, dark maroon as the primary brand color,
/// neutral grays for elevated surfaces. Dark mode: black surface, dark
/// maroon tints for elevated surfaces, maroon for primary accents.
class AppPalette {
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF1A1410); // warm near-black, not pure
  static const blackPure = Color(0xFF000000);
  static const maroon = Color(0xFF5C0E14);
  static const maroonDeep = Color(0xFF3A080C);
  static const maroonSoft = Color(0xFF8B1A24);
}

class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppPalette.maroon,
      onPrimary: AppPalette.white,
      primaryContainer: Color(0xFFEAD4D6),
      onPrimaryContainer: AppPalette.maroonDeep,
      secondary: AppPalette.maroonSoft,
      onSecondary: AppPalette.white,
      secondaryContainer: Color(0xFFEAD4D6),
      onSecondaryContainer: AppPalette.black,
      tertiary: AppPalette.maroonDeep,
      onTertiary: AppPalette.white,
      tertiaryContainer: Color(0xFFEAD4D6),
      onTertiaryContainer: AppPalette.black,
      error: Color(0xFFB3261E),
      onError: AppPalette.white,
      errorContainer: Color(0xFFF9DEDC),
      onErrorContainer: Color(0xFF410E0B),
      surface: AppPalette.white,
      onSurface: AppPalette.black,
      surfaceContainerLowest: AppPalette.white,
      surfaceContainerLow: Color(0xFFFAF5F5),
      surfaceContainer: Color(0xFFF2EAEA),
      surfaceContainerHigh: Color(0xFFE8DADA),
      surfaceContainerHighest: Color(0xFFDCCCCC),
      onSurfaceVariant: Color(0xFF52474A),
      outline: Color(0xFF857075),
      outlineVariant: Color(0xFFD6C7C9),
      inverseSurface: AppPalette.maroonDeep,
      onInverseSurface: Color(0xFFEAD4D6),
      inversePrimary: AppPalette.maroonSoft,
      shadow: AppPalette.black,
      scrim: AppPalette.black,
      surfaceTint: AppPalette.maroon,
    );
    return _base(scheme);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppPalette.maroonSoft,
      onPrimary: AppPalette.white,
      primaryContainer: AppPalette.maroonDeep,
      onPrimaryContainer: Color(0xFFEAD4D6),
      secondary: AppPalette.maroon,
      onSecondary: AppPalette.white,
      secondaryContainer: AppPalette.maroonDeep,
      onSecondaryContainer: Color(0xFFEAD4D6),
      tertiary: AppPalette.maroonSoft,
      onTertiary: AppPalette.white,
      tertiaryContainer: AppPalette.maroonDeep,
      onTertiaryContainer: Color(0xFFEAD4D6),
      error: Color(0xFFF2B8B5),
      onError: Color(0xFF601410),
      errorContainer: Color(0xFF8C1D18),
      onErrorContainer: Color(0xFFF9DEDC),
      surface: AppPalette.blackPure,
      onSurface: AppPalette.white,
      surfaceContainerLowest: AppPalette.blackPure,
      surfaceContainerLow: Color(0xFF0A0A0A),
      surfaceContainer: Color(0xFF101010),
      surfaceContainerHigh: Color(0xFF1A1A1A),
      surfaceContainerHighest: Color(0xFF222222),
      onSurfaceVariant: Color(0xFFBFB3B5),
      outline: Color(0xFF5C4F51),
      outlineVariant: Color(0xFF2A2224),
      inverseSurface: Color(0xFFEAD4D6),
      onInverseSurface: AppPalette.maroonDeep,
      inversePrimary: AppPalette.maroon,
      shadow: AppPalette.blackPure,
      scrim: AppPalette.blackPure,
      surfaceTint: AppPalette.maroonSoft,
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
