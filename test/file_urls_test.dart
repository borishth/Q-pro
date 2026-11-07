import 'package:flutter_test/flutter_test.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:q_pro/core/network/file_urls.dart';
import 'package:q_pro/core/network/session.dart';

/// A real answer URL as the server now writes it, from a submission whose
/// image was stored in object storage.
const _downloadUrl =
    '/api/method/infrive_app.api.files.download'
    '?file=e602edc453&filename=scaled_2c459228-bd5e-4984-8ada-d901.jpg';

void main() {
  setUpAll(() => sdk = FrappeSDK(baseUrl: 'http://10.0.0.5:8800/'));

  group('fileAnswerUrls', () {
    test('reads the list the server now sends', () {
      expect(fileAnswerUrls([_downloadUrl, '/private/files/b.pdf']),
          [_downloadUrl, '/private/files/b.pdf']);
    });

    test('still reads a bare string from before the list change', () {
      expect(fileAnswerUrls('/private/files/a.png'), ['/private/files/a.png']);
    });

    test('treats empty, blank and null as no attachment', () {
      expect(fileAnswerUrls(null), isEmpty);
      expect(fileAnswerUrls(''), isEmpty);
      expect(fileAnswerUrls('   '), isEmpty);
      expect(fileAnswerUrls(const []), isEmpty);
      expect(fileAnswerUrls(const ['', '  ', null]), isEmpty);
    });
  });

  group('absoluteFileUrl', () {
    test('joins a relative path onto the base without doubling the slash', () {
      expect(absoluteFileUrl('/private/files/a.png'),
          'http://10.0.0.5:8800/private/files/a.png');
    });

    test('adds stream=1 so the bytes come from the origin, not a redirect', () {
      expect(absoluteFileUrl(_downloadUrl, stream: true), endsWith('&stream=1'));
    });

    test('never adds stream twice', () {
      final once = absoluteFileUrl(_downloadUrl, stream: true);
      expect(absoluteFileUrl(once, stream: true), once);
    });

    test('leaves a plain file path alone — only the endpoint streams', () {
      expect(absoluteFileUrl('/private/files/a.png', stream: true),
          isNot(contains('stream')));
    });

    test('passes an already-absolute URL straight through', () {
      expect(absoluteFileUrl('https://cdn.test/a.png'), 'https://cdn.test/a.png');
    });
  });

  group('fileNameFromUrl', () {
    test('prefers the filename the download endpoint carries', () {
      expect(fileNameFromUrl(_downloadUrl),
          'scaled_2c459228-bd5e-4984-8ada-d901.jpg');
    });

    test('falls back to the last path segment for a stored file', () {
      expect(fileNameFromUrl('/private/files/site-photo.png'), 'site-photo.png');
    });

    test('never renders the whole endpoint as the name', () {
      expect(fileNameFromUrl(_downloadUrl), isNot(contains('files.download')));
    });
  });
}
