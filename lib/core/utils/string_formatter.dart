/// Shared text-formatting helpers used across screens.
library;

/// A short "Xm ago" / "Xh ago" / "Xd ago" label for a stored
/// `updated_at` epoch-millis timestamp.
String relativeTime(int epochMs) {
  final diff =
      DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Renders a raw answer value (bool/list/scalar/null) as read-only display
/// text for the submission detail screen.
String formatAnswer(dynamic value) {
  if (value == null || value == '') return '—';
  if (value == true) return 'Yes';
  if (value == false) return 'No';
  if (value is List) return value.isEmpty ? '—' : value.join(', ');
  return value.toString();
}
