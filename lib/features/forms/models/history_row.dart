/// One entry in a submission's audit trail.
class HistoryRow {
  const HistoryRow({
    required this.action,
    required this.by,
    this.role,
    this.comment,
    required this.time,
  });

  final String action;
  final String by;
  final String? role;
  final String? comment;
  final String time;

  factory HistoryRow.fromJson(Map<String, dynamic> json) => HistoryRow(
        action: json['action']?.toString() ?? '',
        by: json['action_by']?.toString() ?? '',
        role: json['role_used']?.toString(),
        comment: json['comment']?.toString(),
        time: json['action_time']?.toString() ?? '',
      );
}
