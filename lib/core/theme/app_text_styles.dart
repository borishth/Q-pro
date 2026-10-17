import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography tokens ported from the ConstructionHub design system.
/// Primary font: Sora | Monospace/label font: IBM Plex Mono
class AppTextStyles {
  AppTextStyles._();

  // ── Sora (primary) ──────────────────────────────────────────
  static TextStyle get displayLarge => GoogleFonts.sora(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        letterSpacing: -0.5,
      );

  static TextStyle get headingLarge => GoogleFonts.sora(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.white,
      );

  static TextStyle get headingMedium => GoogleFonts.sora(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      );

  static TextStyle get titleLarge => GoogleFonts.sora(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
        letterSpacing: 0.01,
      );

  static TextStyle get titleMedium => GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      );

  static TextStyle get titleSmall => GoogleFonts.sora(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
        height: 1.35,
      );

  static TextStyle get bodyLarge => GoogleFonts.sora(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.white,
        letterSpacing: 0.02,
      );

  static TextStyle get bodyMedium => GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.muted,
      );

  static TextStyle get bodySmall => GoogleFonts.sora(
        fontSize: 13,
        color: AppColors.muted,
      );

  static TextStyle get caption => GoogleFonts.sora(
        fontSize: 12,
        color: AppColors.muted,
        height: 1.5,
      );

  static TextStyle get link => GoogleFonts.sora(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.orange,
      );

  // ── IBM Plex Mono (labels / breadcrumbs / mono) ────────────
  static TextStyle get mono => GoogleFonts.ibmPlexMono(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.slate,
        letterSpacing: 0.08,
      );

  static TextStyle get monoLabel => GoogleFonts.ibmPlexMono(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: AppColors.slate,
        letterSpacing: 0.06,
      );

  static TextStyle get monoBold => GoogleFonts.ibmPlexMono(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
        letterSpacing: 0.06,
      );

  static TextStyle get monoStat => GoogleFonts.ibmPlexMono(
        fontSize: 10,
        color: AppColors.slate,
      );

  static TextStyle get fieldLabel => GoogleFonts.sora(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.muted,
        letterSpacing: 0.06,
      );

  // ── Stat number ─────────────────────────────────────────────
  static TextStyle get statNumber => GoogleFonts.sora(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.white,
      );
}
