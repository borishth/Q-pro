import '../../../core/models/permissions.dart';
import '../../forms/models/form_summary.dart';

/// Response of `hierarchy.get_stage`: per-resource permission flags, the
/// Active forms on this stage, and submission counts.
class StageDashboard {
  const StageDashboard({
    required this.id,
    required this.name,
    required this.permissions,
    required this.forms,
    required this.submissionCounts,
  });

  final String id;
  final String name;
  final Map<String, Permissions> permissions;
  final List<FormSummary> forms;
  final Map<String, int> submissionCounts;

  Permissions of(String resource) => permissions[resource] ?? Permissions.none;

  factory StageDashboard.fromJson(Map<String, dynamic> json) =>
      StageDashboard(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        permissions: {
          for (final e in (json['permissions'] as Map? ?? const {}).entries)
            e.key.toString(): Permissions.fromJson(
              Map<String, dynamic>.from(e.value as Map? ?? const {}),
            ),
        },
        forms: [
          for (final f in (json['forms'] as List? ?? const []))
            FormSummary.fromJson(Map<String, dynamic>.from(f as Map)),
        ],
        submissionCounts: {
          for (final e
              in (json['submission_counts'] as Map? ?? const {}).entries)
            e.key.toString(): (e.value as num?)?.toInt() ?? 0,
        },
      );
}
