import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'session.dart';

/// Uploads one attachment, returning its `file_url`. Injected into
/// [OutboxSync] so tests can stand in for the network.
typedef AttachmentUploader = Future<String> Function(
  File file, {
  required String submission,
});

/// Uploads [file] as an attachment of [submission] and returns its
/// `file_url`.
///
/// Deliberately not `sdk.api.attachment.uploadFile`. That sends the legacy
/// `dt`/`dn` field names, but `/api/method/upload_file` reads `doctype`
/// and `docname` — so it ignores them and creates the File row with no
/// `attached_to_doctype`. The upload looks like it worked, and the
/// uploader can even see their own image, because
/// `infrive_app.api.files.download` lets an owner through. Everyone else
/// is refused: with nothing attached there is no submission to authorize
/// against, so an approver opening the form gets a broken image. The web
/// frontend sends the modern names; this matches it.
Future<String> uploadAttachment(
  File file, {
  required String submission,
}) async {
  final base = sdk.baseUrl.endsWith('/')
      ? sdk.baseUrl.substring(0, sdk.baseUrl.length - 1)
      : sdk.baseUrl;

  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$base/api/method/upload_file'),
  )
    // Accept plus the auth header or session cookie. No Content-Type among
    // them, so the multipart boundary this request sets for itself stands.
    ..headers.addAll(sdk.api.requestHeaders)
    ..fields['is_private'] = '1'
    ..fields['folder'] = 'Home'
    ..fields['doctype'] = 'Form Submission'
    ..fields['docname'] = submission
    ..files.add(await http.MultipartFile.fromPath('file', file.path));

  final response = await http.Response.fromStream(await request.send());
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Upload failed (HTTP ${response.statusCode}).',
      uri: request.url,
    );
  }

  final body = jsonDecode(response.body);
  final message = body is Map ? body['message'] : null;
  final url = message is Map ? message['file_url']?.toString() : null;
  if (url == null || url.isEmpty) {
    throw const FormatException('Upload did not return a file URL.');
  }
  return url;
}
