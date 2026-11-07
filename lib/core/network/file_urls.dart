import 'session.dart';

/// The endpoint `storage/s3.py` rewrites `file_url` to once object storage
/// is switched on. Files written before that keep their `/private/files/...`
/// path, so both shapes are in play at the same time.
const _downloadPath = '/api/method/infrive_app.api.files.download';

/// A File/Image answer as a list of URLs.
///
/// The server stores these as a JSON list — a bare string is accepted on
/// write and read back as a one-item list — and answers saved before that
/// change still arrive as a plain string. Normalize both rather than
/// casting, which throws on whichever shape you didn't expect.
List<String> fileAnswerUrls(dynamic value) {
  if (value == null) return const [];
  final raw = value is List ? value : [value];
  return [
    for (final item in raw)
      if (item != null && item.toString().trim().isNotEmpty)
        item.toString().trim(),
  ];
}

/// Absolute URL for a stored attachment, to be loaded with
/// `sdk.api.requestHeaders` so the auth header rides along.
///
/// [stream] asks the download endpoint for the bytes inline instead of a
/// redirect to a presigned object-storage URL. A device needs that: the
/// presigned host comes from the server's `s3_endpoint`, which on a LAN
/// bench is `127.0.0.1` — on a phone that resolves to the phone itself, so
/// the redirect leads nowhere and the image fails with no visible reason.
/// Streaming keeps the bytes on the origin the app already talks to. A
/// deployment whose object storage is reachable from the handset can drop
/// the flag and get the redirect (and its offload) back.
String absoluteFileUrl(String url, {bool stream = false}) {
  final wantsStream =
      stream && url.contains(_downloadPath) && !url.contains('stream=');
  final full = wantsStream
      ? '$url${url.contains('?') ? '&' : '?'}stream=1'
      : url;

  if (full.startsWith('http://') || full.startsWith('https://')) return full;

  final base = sdk.baseUrl.endsWith('/')
      ? sdk.baseUrl.substring(0, sdk.baseUrl.length - 1)
      : sdk.baseUrl;
  return '$base${full.startsWith('/') ? full : '/$full'}';
}

/// Display name for an attachment URL. The download endpoint carries the
/// original name in a `filename` query parameter; a plain path falls back
/// to its last segment. Without this a download URL renders as the whole
/// `...files.download?file=<hash>&filename=<name>` string.
String fileNameFromUrl(String url) {
  final uri = Uri.tryParse(url);

  final fromQuery = uri?.queryParameters['filename']?.trim();
  if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;

  final segments = uri?.pathSegments ?? const <String>[];
  if (segments.isNotEmpty && segments.last.isNotEmpty) return segments.last;

  return url.split('/').last;
}
