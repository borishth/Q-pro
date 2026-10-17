import 'package:flutter_test/flutter_test.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:q_pro/core/network/app_errors.dart';

void main() {
  group('describeError', () {
    test('unwraps a FrappeException to its message', () {
      expect(describeError(ApiException('Server exploded', 500)), 'Server exploded');
    });

    test('falls back to toString for a non-Frappe error', () {
      expect(describeError(Exception('boom')), contains('boom'));
    });
  });

  group('isSessionExpired', () {
    test('true only for a 401 AuthException', () {
      expect(isSessionExpired(AuthException('Unauthorized', 401)), isTrue);
    });

    test('false for a 403 AuthException (forbidden, not signed out)', () {
      expect(isSessionExpired(AuthException('Forbidden', 403)), isFalse);
    });

    test('false for a ValidationException', () {
      expect(isSessionExpired(ValidationException('Missing field')), isFalse);
    });

    test('false for a non-Frappe error', () {
      expect(isSessionExpired(Exception('boom')), isFalse);
    });
  });
}
