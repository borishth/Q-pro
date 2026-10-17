import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../models/hierarchy.dart';

/// Picks an icon for a stage based on keywords in its name/type — purely
/// cosmetic categorisation (ported from the ConstructionHub design), the
/// backend has no icon field of its own.
IconData stageIcon(StageNode node) {
  final lower = '${node.name} ${node.type}'.toLowerCase();
  if (lower.contains('civil') ||
      lower.contains('concrete') ||
      lower.contains('foundation') ||
      lower.contains('rebar')) {
    return Icons.foundation_outlined;
  }
  if (lower.contains('electrical') || lower.contains('power') || lower.contains('mep')) {
    return Icons.electrical_services_outlined;
  }
  if (lower.contains('road') || lower.contains('pavement')) {
    return Icons.edit_road_outlined;
  }
  if (lower.contains('water') || lower.contains('plumbing')) {
    return Icons.water_drop_outlined;
  }
  if (lower.contains('finish') ||
      lower.contains('plaster') ||
      lower.contains('tile') ||
      lower.contains('brick') ||
      lower.contains('facade')) {
    return Icons.architecture_outlined;
  }
  if (lower.contains('safety') || lower.contains('hse')) {
    return Icons.health_and_safety_outlined;
  }
  return Icons.layers_outlined;
}

Color stageColor(StageNode node) {
  final lower = '${node.name} ${node.type}'.toLowerCase();
  if (lower.contains('civil') || lower.contains('concrete')) return AppColors.navy;
  if (lower.contains('electrical') || lower.contains('mep')) return AppColors.green;
  if (lower.contains('road')) return AppColors.orange;
  if (lower.contains('water')) return Colors.blue;
  if (lower.contains('finish') || lower.contains('brick') || lower.contains('facade')) {
    return Colors.teal;
  }
  if (lower.contains('safety')) return AppColors.red;
  return AppColors.slate;
}

/// A single stage/sub-phase row card, shared by the top-level stage list
/// and by a stage's own sub-phases list. A stage is tappable whenever it's
/// reachable (opens its own forms) or has children to drill into — a
/// `contextOnly` organisational node with no view permission of its own
/// still needs to be drillable so its reachable descendants stay reachable.
/// Only a true dead end (no children, not reachable) renders disabled.
class StageFolderCard extends StatelessWidget {
  const StageFolderCard({super.key, required this.node, required this.onTap});

  final StageNode node;
  final VoidCallback onTap;

  bool get _tappable => node.isReachable || node.children.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final tappable = _tappable;
    final icon = stageIcon(node);
    final color = tappable ? stageColor(node) : AppColors.slate;

    final subtitleParts = [
      '${node.children.length.toString().padLeft(2, '0')} sub-phases',
      if (node.code.isNotEmpty) node.code,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: tappable ? 1 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: tappable ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          style: GoogleFonts.sora(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitleParts.join(' · '),
                          style: GoogleFonts.sora(
                            fontSize: 11,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    tappable ? Icons.chevron_right_rounded : Icons.lock_outline_rounded,
                    color: AppColors.slate,
                    size: tappable ? 20 : 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
