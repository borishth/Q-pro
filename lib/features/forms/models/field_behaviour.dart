/// Parses the extra `;`-separated tokens the web form builder packs into a
/// question's `rule` string — `readonly`, `hidden`, `depends_on:<expr>`,
/// `link:<form id>` — since the backend has no dedicated columns for them.
/// Unrecognised tokens (min/max/regex/...) are left in [validationRule].
class FieldBehaviour {
  const FieldBehaviour({
    required this.validationRule,
    required this.readOnly,
    required this.hidden,
    required this.dependsOn,
    required this.link,
  });

  final String validationRule;
  final bool readOnly;
  final bool hidden;
  final String dependsOn;
  final String link;

  factory FieldBehaviour.parse(String? raw) {
    var readOnly = false;
    var hidden = false;
    var dependsOn = '';
    var link = '';
    final rest = <String>[];

    for (final part in (raw ?? '')
        .split(RegExp(r'[;\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)) {
      if (part == 'readonly') {
        readOnly = true;
      } else if (part == 'hidden') {
        hidden = true;
      } else if (part.startsWith('depends_on:')) {
        dependsOn = part.substring('depends_on:'.length);
      } else if (part.startsWith('link:')) {
        link = part.substring('link:'.length);
      } else {
        rest.add(part);
      }
    }

    return FieldBehaviour(
      validationRule: rest.join(';'),
      readOnly: readOnly,
      hidden: hidden,
      dependsOn: dependsOn,
      link: link,
    );
  }
}

/// Evaluates a `depends_on` expression (`CODE=value`, `CODE!=value`, or a
/// bare `CODE` meaning "answered") against the current answers. Conditions
/// joined by `&` must all hold.
bool dependsMet(String expr, Map<String, dynamic> answers) {
  bool isBlank(dynamic v) =>
      v == null || v == '' || v == false || (v is List && v.isEmpty);

  String asText(dynamic v) {
    if (v == true) return 'yes';
    if (v == false) return 'no';
    if (v is List) return v.join(',').toLowerCase();
    return '${v ?? ''}'.toLowerCase();
  }

  return expr
      .split('&')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .every((condition) {
    final match =
        RegExp(r'^([^=!]+?)\s*(!=|=)\s*(.*)$').firstMatch(condition);
    if (match == null) return !isBlank(answers[condition]);

    final answer = answers[match[1]!.trim()];
    final value = match[3]!.trim().toLowerCase();
    final hit = answer is List
        ? answer.map((x) => '$x'.toLowerCase()).contains(value)
        : asText(answer) == value;
    return match[2] == '=' ? hit : !hit;
  });
}
