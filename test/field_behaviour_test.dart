import 'package:flutter_test/flutter_test.dart';
import 'package:q_pro/features/forms/models/field_behaviour.dart';

void main() {
  group('FieldBehaviour.parse', () {
    test('null/empty rule yields all defaults', () {
      final b = FieldBehaviour.parse(null);
      expect(b.readOnly, isFalse);
      expect(b.hidden, isFalse);
      expect(b.dependsOn, isEmpty);
      expect(b.link, isEmpty);
      expect(b.validationRule, isEmpty);
    });

    test('readonly token', () {
      expect(FieldBehaviour.parse('readonly').readOnly, isTrue);
    });

    test('hidden token', () {
      expect(FieldBehaviour.parse('hidden').hidden, isTrue);
    });

    test('depends_on token captures the expression', () {
      final b = FieldBehaviour.parse('depends_on:STATUS=done');
      expect(b.dependsOn, 'STATUS=done');
    });

    test('link token captures the target form id', () {
      final b = FieldBehaviour.parse('link:FORM-42');
      expect(b.link, 'FORM-42');
    });

    test('unrecognised tokens are preserved in validationRule, known ones stripped out', () {
      final b = FieldBehaviour.parse('min:0;readonly;max:100;hidden');
      expect(b.readOnly, isTrue);
      expect(b.hidden, isTrue);
      expect(b.validationRule, 'min:0;max:100');
    });

    test('tokens separated by newlines are parsed the same as semicolons', () {
      final b = FieldBehaviour.parse('readonly\nhidden');
      expect(b.readOnly, isTrue);
      expect(b.hidden, isTrue);
    });

    test('multiple tokens combine correctly', () {
      final b = FieldBehaviour.parse('depends_on:A=1;link:FORM-1;readonly');
      expect(b.dependsOn, 'A=1');
      expect(b.link, 'FORM-1');
      expect(b.readOnly, isTrue);
      expect(b.hidden, isFalse);
    });
  });

  group('dependsMet', () {
    test('bare code means "has been answered"', () {
      expect(dependsMet('NOTES', {'NOTES': 'something'}), isTrue);
      expect(dependsMet('NOTES', {'NOTES': ''}), isFalse);
      expect(dependsMet('NOTES', {}), isFalse);
    });

    test('equality match is case-insensitive', () {
      expect(dependsMet('STATUS=Done', {'STATUS': 'done'}), isTrue);
      expect(dependsMet('STATUS=Done', {'STATUS': 'DONE'}), isTrue);
      expect(dependsMet('STATUS=Done', {'STATUS': 'pending'}), isFalse);
    });

    test('inequality match', () {
      expect(dependsMet('STATUS!=done', {'STATUS': 'pending'}), isTrue);
      expect(dependsMet('STATUS!=done', {'STATUS': 'done'}), isFalse);
    });

    test('yes_no (bool) answers compare as yes/no', () {
      expect(dependsMet('APPROVED=yes', {'APPROVED': true}), isTrue);
      expect(dependsMet('APPROVED=no', {'APPROVED': false}), isTrue);
      expect(dependsMet('APPROVED=yes', {'APPROVED': false}), isFalse);
    });

    test('list answers match via contains for equality', () {
      expect(
        dependsMet('TAGS=urgent', {
          'TAGS': ['urgent', 'site-a'],
        }),
        isTrue,
      );
      expect(
        dependsMet('TAGS=urgent', {
          'TAGS': ['site-a'],
        }),
        isFalse,
      );
    });

    test('an empty list answer counts as blank for the bare-code form', () {
      expect(dependsMet('TAGS', {'TAGS': <String>[]}), isFalse);
    });

    test('multiple & conditions all require to hold', () {
      final answers = {'A': 'yes', 'B': 'no'};
      expect(dependsMet('A=yes&B=no', answers), isTrue);
      expect(dependsMet('A=yes&B=yes', answers), isFalse);
    });

    test('unanswered question used in a comparison does not match', () {
      expect(dependsMet('STATUS=done', {}), isFalse);
    });
  });
}
