import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Status tag pill (ported from the ConstructionHub design system): a small
/// dot + label, e.g. "IN PROGRESS" / "PAUSED" / "CRITICAL".
enum TagType { green, yellow, red }

class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.label, required this.type});

  final String label;
  final TagType type;

  Color get _bg => switch (type) {
        TagType.green => AppColors.tagGreenBg,
        TagType.yellow => AppColors.tagYellowBg,
        TagType.red => AppColors.tagRedBg,
      };

  Color get _fg => switch (type) {
        TagType.green => AppColors.green,
        TagType.yellow => AppColors.yellow,
        TagType.red => AppColors.red,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _fg.withValues(alpha: 0.16), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: _fg, shape: BoxShape.circle),
          ),
          Text(
            label,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _fg,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
