/// One row from `workflow.get_inbox`: a submission waiting on the current
/// user (by role assignment or ownership), already filtered server-side.
class InboxRow {
  const InboxRow({
    required this.name,
    required this.form,
    required this.project,
    required this.stage,
    required this.status,
    this.currentRole,
    this.currentAssignee,
    this.modified,
  });

  final String name;
  final String form;
  final String project;
  final String stage;
  final String status;
  final String? currentRole;
  final String? currentAssignee;
  final String? modified;

  factory InboxRow.fromJson(Map<String, dynamic> json) => InboxRow(
        name: json['name']?.toString() ?? '',
        form: json['form']?.toString() ?? '',
        project: json['project']?.toString() ?? '',
        stage: json['stage']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        currentRole: json['current_role']?.toString(),
        currentAssignee: json['current_assignee']?.toString(),
        modified: json['modified']?.toString(),
      );
}
