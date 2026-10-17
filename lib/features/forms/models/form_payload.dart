import 'question.dart';

/// The question list for one form, embedded in a [SubmissionDetail] as
/// `form_payload`.
class FormPayload {
  const FormPayload({
    required this.id,
    required this.title,
    required this.version,
    required this.questions,
  });

  final String id;
  final String title;
  final int version;
  final List<Question> questions;

  factory FormPayload.fromJson(Map<String, dynamic> json) => FormPayload(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        version: (json['version'] as num?)?.toInt() ?? 1,
        questions: [
          for (final q in (json['questions'] as List? ?? const []))
            Question.fromJson(Map<String, dynamic>.from(q as Map)),
        ],
      );
}
