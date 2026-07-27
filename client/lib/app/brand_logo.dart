import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Brand wordmark. Picks the light or dark variant based on the active theme
/// brightness so the logo stays readable in both modes.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 24});
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      'assets/brand/riff-${isDark ? 'dark' : 'light'}.svg',
      height: height,
      // The SVG is a single-color wordmark; let the theme's foreground drive
      // the color so it inverts cleanly with the app bar.
      colorFilter: ColorFilter.mode(
        Theme.of(context).colorScheme.onSurface,
        BlendMode.srcIn,
      ),
      semanticsLabel: 'Riff',
    );
  }
}
