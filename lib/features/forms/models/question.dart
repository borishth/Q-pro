/// One question inside a [FormPayload]. `type` is one of: text, textarea,
/// number, currency, rating, date, datetime, yes_no, checkbox, select,
/// radio, multi_select, table, file, image, signature. `rule` may carry
/// extra behaviour tokens — see `FieldBehaviour.parse`.
class Question {
  const Question({
    required this.id,
    required this.type,
    required this.label,
    required this.required,
    this.options = const [],
    this.help,
    this.rule,
    this.parent,
    this.defaultValue,
  });

  final String id;
  final String type;
  final String label;
  final bool required;
  final List<String> options;
  final String? help;
  final String? rule;
  final String? parent;
  final String? defaultValue;

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? 'text',
        label: json['label']?.toString() ?? '',
        required: json['required'] == true,
        options: [
          for (final o in (json['options'] as List? ?? const [])) '$o',
        ],
        help: json['help']?.toString(),
        rule: json['rule']?.toString(),
        parent: json['parent']?.toString(),
        defaultValue: json['default']?.toString(),
      );
}
