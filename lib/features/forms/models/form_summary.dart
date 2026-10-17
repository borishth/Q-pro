/// One row from `forms.get_stage_forms`.
class FormSummary {
  const FormSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.version,
  });

  final String id;
  final String title;
  final String status;
  final int version;

  bool get isActive => status == 'Active';

  factory FormSummary.fromJson(Map<String, dynamic> json) => FormSummary(
        id: json['id']?.toString() ?? json['name']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Untitled form',
        status: json['status']?.toString() ?? 'Unknown',
        version: (json['version'] as num?)?.toInt() ?? 1,
      );
}
