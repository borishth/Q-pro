import 'package:flutter/material.dart';

/// Design tokens ported from the ConstructionHub design system so q_pro's
/// screens read as one consistent product instead of default Material.
class AppColors {
  AppColors._();

  // Primary palette
  static const Color navy = Color(0xFF0A192F);
  static const Color navy2 = Color(0xFF0F2340);
  static const Color navy3 = Color(0xFF1A3A5C);

  static const Color orange = Color(0xFFFF6B00);
  static const Color orange2 = Color(0xFFE85F00);

  // Neutral
  static const Color slate = Color(0xFF8B9DB5);
  static const Color light = Color(0xFFF4F6F9);
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFE8ECF1);

  // Semantic
  static const Color green = Color(0xFF1A9E5C);
  static const Color yellow = Color(0xFFD4A017);
  static const Color red = Color(0xFFC0392B);

  // Text
  static const Color text = Color(0xFF1A2B3C);
  static const Color muted = Color(0xFF6B7C93);
  static const Color border = Color(0xFFDCE3ED);

  // Tag backgrounds
  static const Color tagGreenBg = Color(0xFFE8F5ED);
  static const Color tagYellowBg = Color(0xFFFEF8E7);
  static const Color tagRedBg = Color(0xFFFDECEA);

  // Gradient icon-chip pairs (category accents for quick-action grids)
  static const List<Color> gradientOrange = [Color(0xFFFB923C), Color(0xFFF59E0B)];
  static const List<Color> gradientEmerald = [Color(0xFF34D399), Color(0xFF14B8A6)];
  static const List<Color> gradientBlue = [Color(0xFF3B82F6), Color(0xFF22D3EE)];
  static const List<Color> gradientPurple = [Color(0xFF6366F1), Color(0xFF9333EA)];
  static const List<Color> gradientNavy = [Color(0xFF1A3A5C), Color(0xFF0A192F)];

  /// Soft colored glow shadow for elevated cards/buttons on light
  /// backgrounds. Prefer the named tiers below over one-off numbers.
  static List<BoxShadow> glowShadow(
    Color color, {
    required double opacity,
    required double blur,
    required double offsetY,
  }) {
    return [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blur,
        offset: Offset(0, offsetY),
      ),
    ];
  }

  static List<BoxShadow> glowSubtle(Color color) =>
      glowShadow(color, opacity: 0.18, blur: 12, offsetY: 4);

  static List<BoxShadow> glowMedium(Color color) =>
      glowShadow(color, opacity: 0.28, blur: 20, offsetY: 8);

  static List<BoxShadow> glowStrong(Color color) =>
      glowShadow(color, opacity: 0.34, blur: 32, offsetY: 12);

  /// Neutral soft elevation shadow for light-surface cards (no color tint).
  static const List<BoxShadow> softShadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];
}

/// Standard spacing scale — use these instead of arbitrary padding/gap
/// numbers so density stays consistent across screens.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}
