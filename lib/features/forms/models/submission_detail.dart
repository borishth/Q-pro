import '../../../core/models/permissions.dart';
import 'form_payload.dart';
import 'history_row.dart';
import 'transition.dart';

/// Response of `forms.get_submission`, `forms.save_submission` and
/// `forms.submit_submission`: the full state of one Form Submission for
/// the current user, including the form's question payload.
class SubmissionDetail {
  const SubmissionDetail({
    required this.name,
    required this.status,
    required this.project,
    required this.stage,
    required this.form,
    required this.answers,
    required this.editable,
    required this.permissions,
    required this.transitions,
    required this.history,
    this.currentRole,
    this.currentAssignee,
  });

  final String name;
  final String status;
  final String project;
  final String stage;
  final FormPayload form;
  final Map<String, dynamic> answers;
  final bool editable;
  final Permissions permissions;
  final List<Transition> transitions;
  final List<HistoryRow> history;
  final String? currentRole;
  final String? currentAssignee;

  factory SubmissionDetail.fromJson(Map<String, dynamic> json) =>
      SubmissionDetail(
        name: json['name']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        project: json['project']?.toString() ?? '',
        stage: json['stage']?.toString() ?? '',
        form: FormPayload.fromJson(
          Map<String, dynamic>.from(json['form_payload'] as Map? ?? const {}),
        ),
        answers:
            Map<String, dynamic>.from(json['answers'] as Map? ?? const {}),
        editable: json['editable'] == true,
        permissions: Permissions.fromJson(
          json['permissions'] as Map<String, dynamic>?,
        ),
        transitions: [
          for (final t in (json['transitions'] as List? ?? const []))
            Transition.fromJson(Map<String, dynamic>.from(t as Map)),
        ],
        history: [
          for (final h in (json['history'] as List? ?? const []))
            HistoryRow.fromJson(Map<String, dynamic>.from(h as Map)),
        ],
        currentRole: json['current_role']?.toString(),
        currentAssignee: json['current_assignee']?.toString(),
      );
}
