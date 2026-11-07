/// One entry in a submission's audit trail.
class HistoryRow {
  const HistoryRow({
    required this.action,
    required this.by,
    this.role,
    this.comment,
    this.rating = 0,
    this.ratingRemark,
    required this.time,
  });

  final String action;
  final String by;
  final String? role;
  final String? comment;

  /// Compliance rating given with this action, or 0 when it carried none.
  final int rating;

  /// The label the approver saw, snapshotted server-side at the time —
  /// preferred over [ratingLabel] so rewording the scale never rewrites
  /// history.
  final String? ratingRemark;
  final String time;

  factory HistoryRow.fromJson(Map<String, dynamic> json) => HistoryRow(
        action: json['action']?.toString() ?? '',
        by: json['action_by']?.toString() ?? '',
        role: json['role_used']?.toString(),
        comment: json['comment']?.toString(),
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        ratingRemark: json['rating_remark']?.toString(),
        time: json['action_time']?.toString() ?? '',
      );
}
