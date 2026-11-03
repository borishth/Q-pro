/// One row from `notifications.list_notifications`: something that happened
/// to a submission that this user should hear about.
///
/// The server renders [title] and [body] — including the role name, which
/// is a display name like "manager" rather than an id like
/// `PRJ-00001-001_COPY` — so the wording lives in one place instead of
/// being reassembled on every client.
class AppNotification {
  const AppNotification({
    required this.name,
    required this.kind,
    required this.title,
    required this.body,
    required this.isRead,
    this.submission,
    this.form,
    this.project,
    this.stage,
    this.roleName,
    this.actor,
    this.createdAt,
  });

  final String name;

  /// What happened, as sent by the server: `sent_for_approval`,
  /// `awaiting_action`, `approved`, `rework` or `rejected`. Anything
  /// unrecognised still renders — it just falls back to a neutral icon.
  final String kind;

  final String title;
  final String body;
  final bool isRead;
  final String? submission;
  final String? form;
  final String? project;
  final String? stage;
  final String? roleName;
  final String? actor;
  final String? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        name: json['name']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        isRead: json['is_read'] == true || json['is_read'] == 1,
        submission: json['submission']?.toString(),
        form: json['form']?.toString(),
        project: json['project']?.toString(),
        stage: json['stage']?.toString(),
        roleName: json['role_name']?.toString(),
        actor: json['actor']?.toString(),
        createdAt: json['creation']?.toString(),
      );

  AppNotification copyWith({bool? isRead}) => AppNotification(
        name: name,
        kind: kind,
        title: title,
        body: body,
        isRead: isRead ?? this.isRead,
        submission: submission,
        form: form,
        project: project,
        stage: stage,
        roleName: roleName,
        actor: actor,
        createdAt: createdAt,
      );
}
