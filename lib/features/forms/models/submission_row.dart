/// One row from `forms.get_submissions` — a lighter-weight listing than
/// [SubmissionDetail], used for the submissions list and the link-field
/// picker.
class SubmissionRow {
  const SubmissionRow({
    required this.name,
    required this.form,
    required this.project,
    required this.stage,
    required this.status,
    this.currentRole,
    this.currentAssignee,
    this.modified,
    this.submittedBy,
  });

  final String name;
  final String form;
  final String project;
  final String stage;
  final String status;
  final String? currentRole;
  final String? currentAssignee;
  final String? modified;
  final String? submittedBy;

  factory SubmissionRow.fromJson(Map<String, dynamic> json) => SubmissionRow(
        name: json['name']?.toString() ?? '',
        form: json['form']?.toString() ?? '',
        project: json['project']?.toString() ?? '',
        stage: json['stage']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        currentRole: json['current_role']?.toString(),
        currentAssignee: json['current_assignee']?.toString(),
        modified: json['modified']?.toString(),
        submittedBy: json['submitted_by']?.toString(),
      );
}
