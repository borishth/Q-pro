import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// A circular gradient avatar showing up to two initials — the dashboard
/// header, sticky mini-header, and Profile screen all use the same one.
class UserAvatar extends StatelessWidget {
  final double radius;
  final String initials;

  const UserAvatar({super.key, required this.radius, required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: AppColors.gradientNavy),
        boxShadow: AppColors.glowMedium(AppColors.navy),
      ),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: GoogleFonts.sora(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
