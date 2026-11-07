import 'package:flutter_test/flutter_test.dart';
import 'package:q_pro/core/models/permissions.dart';
import 'package:q_pro/features/auth/models/me.dart';
import 'package:q_pro/features/forms/models/field_behaviour.dart';
import 'package:q_pro/features/forms/models/history_row.dart';
import 'package:q_pro/features/forms/models/rating_scale.dart';
import 'package:q_pro/features/forms/models/submission_detail.dart';
import 'package:q_pro/features/forms/models/transition.dart';
import 'package:q_pro/features/inbox/models/inbox_row.dart';
import 'package:q_pro/features/projects/models/project.dart';

void main() {
  group('Project.fromJson', () {
    test('parses a full server response', () {
      final p = Project.fromJson({
        'name': 'PROJ-001',
        'project_name': 'Harbor Bridge Retrofit',
        'project_code': 'HBR',
        'status': 'Open',
        'project_manager': 'Administrator',
        'start_date': '2026-01-01',
        'end_date': '2026-12-31',
        'is_active': true,
      });
      expect(p.name, 'PROJ-001');
      expect(p.projectName, 'Harbor Bridge Retrofit');
      expect(p.isActive, isTrue);
    });

    test('defensively fills in missing fields instead of throwing', () {
      final p = Project.fromJson({'name': 'PROJ-002'});
      expect(p.name, 'PROJ-002');
      expect(p.projectName, 'Unnamed project');
      expect(p.status, 'Unknown');
      expect(p.isActive, isFalse);
    });

    test('is_active accepts both 1 and true from the server', () {
      expect(Project.fromJson({'is_active': 1}).isActive, isTrue);
      expect(Project.fromJson({'is_active': 0}).isActive, isFalse);
    });
  });

  group('Me.fromJson', () {
    test('parses role flags', () {
      final me = Me.fromJson({
        'user': 'admin@example.com',
        'full_name': 'Administrator',
        'is_superadmin': true,
        'is_project_admin': false,
      });
      expect(me.isSuperadmin, isTrue);
      expect(me.isProjectAdmin, isFalse);
    });
  });

  group('Permissions.fromJson', () {
    test('coerces 1/true to can(), leaves everything else false', () {
      final perms = Permissions.fromJson({
        'view': true,
        'create': 1,
        'delete': false,
        'approve': 0,
      });
      expect(perms.can('view'), isTrue);
      expect(perms.can('create'), isTrue);
      expect(perms.can('delete'), isFalse);
      expect(perms.can('approve'), isFalse);
    });

    test('null input yields Permissions.none behaviour', () {
      expect(Permissions.fromJson(null).can('view'), isFalse);
    });
  });

  group('InboxRow.fromJson', () {
    test('parses an inbox entry', () {
      final row = InboxRow.fromJson({
        'name': 'SUB-0001',
        'form': 'FORM-1',
        'project': 'PROJ-001',
        'stage': 'STAGE-1',
        'status': 'Draft',
        'current_role': 'Inspector',
      });
      expect(row.name, 'SUB-0001');
      expect(row.currentRole, 'Inspector');
      expect(row.currentAssignee, isNull);
    });
  });

  group('SubmissionDetail.fromJson', () {
    test('parses a full submission with nested form payload, permissions, and history', () {
      final detail = SubmissionDetail.fromJson({
        'name': 'SUB-0002',
        'status': 'Submitted',
        'project': 'PROJ-001',
        'stage': 'STAGE-1',
        'form_payload': {
          'id': 'FORM-1',
          'title': 'Daily Log',
          'version': 1,
          'questions': [
            {'id': 'q1', 'type': 'text', 'label': 'Notes', 'required': false},
          ],
        },
        'answers': {'q1': 'Poured footings today'},
        'editable': false,
        'permissions': {'edit': true, 'delete': true},
        'transitions': [],
        'history': [
          {
            'action': 'Submit',
            'action_by': 'admin@example.com',
            'action_time': '2026-10-15 19:19:05',
          },
        ],
      });

      expect(detail.name, 'SUB-0002');
      expect(detail.form.questions, hasLength(1));
      expect(detail.form.questions.first.label, 'Notes');
      expect(detail.answers['q1'], 'Poured footings today');
      expect(detail.permissions.can('edit'), isTrue);
      expect(detail.history, hasLength(1));
      expect(detail.history.first.action, 'Submit');
      expect(detail.transitions, isEmpty);
    });

    test('a question with a link: rule token parses into FieldBehaviour correctly', () {
      final detail = SubmissionDetail.fromJson({
        'name': 'SUB-0003',
        'form_payload': {
          'id': 'FORM-2',
          'title': 'Inspection',
          'version': 1,
          'questions': [
            {
              'id': 'q2',
              'type': 'text',
              'label': 'Related submission',
              'required': false,
              'rule': 'link:FORM-9',
            },
          ],
        },
      });

      final behaviour = FieldBehaviour.parse(detail.form.questions.first.rule);
      expect(behaviour.link, 'FORM-9');
    });
  });

  group('Transition.requiresRating', () {
    Transition t(String permissionAction) => Transition.fromJson({
          'action': 'Approve',
          'permission_action': permissionAction,
        });

    test('only approvals carry a rating', () {
      expect(t('approve').requiresRating, isTrue);
      expect(t('reject').requiresRating, isFalse);
      expect(t('submit').requiresRating, isFalse);
      expect(t('cancel').requiresRating, isFalse);
    });
  });

  group('HistoryRow.fromJson', () {
    test('parses a rated approval', () {
      final row = HistoryRow.fromJson({
        'action': 'Approve',
        'action_by': 'ravi@infrive.test',
        'role_used': 'ROLE-001',
        'rating': 4,
        'rating_remark': 'High Quality Standards Verified',
        'action_time': '2026-11-05 10:00:00',
      });
      expect(row.rating, 4);
      expect(row.ratingRemark, 'High Quality Standards Verified');
    });

    test('an unrated action reads as 0 with no remark', () {
      final row = HistoryRow.fromJson({
        'action': 'Submit',
        'action_by': 'suresh@infrive.test',
      });
      expect(row.rating, 0);
      expect(row.ratingRemark, isNull);
    });

    test('keeps the stored remark even when the local scale disagrees', () {
      // The server snapshots the label it showed the approver; a reworded
      // scale here must not rewrite history.
      final row = HistoryRow.fromJson({
        'action': 'Approve',
        'action_by': 'amit@infrive.test',
        'rating': 2,
        'rating_remark': 'Wording the app no longer uses',
      });
      expect(row.ratingRemark, isNot(ratingLabel(2)));
    });
  });

  group('ratingScale', () {
    test('covers exactly 1-5, matching the backend RATING_LABELS', () {
      expect(ratingScale.keys, [1, 2, 3, 4, 5]);
      expect(minRating, 1);
      expect(maxRating, 5);
    });

    test('labels only resolve inside the scale', () {
      expect(ratingLabel(1), 'Critical Non-Compliance');
      expect(ratingLabel(5), 'Outstanding Quality & Zero Defects');
      expect(ratingLabel(null), isNull);
      expect(ratingLabel(0), isNull);
      expect(ratingLabel(6), isNull);
    });
  });
}
