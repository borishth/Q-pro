/// One workflow action available on a [SubmissionDetail] right now (e.g.
/// Submit, Approve, Reject) — already filtered server-side to what the
/// current user may do.
class Transition {
  const Transition({
    required this.action,
    required this.permissionAction,
    required this.requiresComment,
  });

  final String action;
  final String permissionAction;
  final bool requiresComment;

  factory Transition.fromJson(Map<String, dynamic> json) => Transition(
        action: json['action']?.toString() ?? '',
        permissionAction: json['permission_action']?.toString() ?? '',
        requiresComment: json['requires_comment'] == true,
      );
}
