/// Action flags the server returns for a resource (Stage, Form, Form
/// Submission, Workflow, ...). The UI only reads these to decide what to
/// show; every write is still re-checked server-side regardless.
class Permissions {
  const Permissions(this._flags);

  final Map<String, bool> _flags;

  static const none = Permissions({});

  factory Permissions.fromJson(Map<String, dynamic>? json) => Permissions({
        for (final e in (json ?? {}).entries)
          e.key.toString(): e.value == true || e.value == 1,
      });

  bool can(String action) => _flags[action] ?? false;
}
