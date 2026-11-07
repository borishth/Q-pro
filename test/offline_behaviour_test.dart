import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:q_pro/core/models/permissions.dart';
import 'package:q_pro/core/network/infrive_api.dart';
import 'package:q_pro/core/services/connectivity_service.dart';
import 'package:q_pro/core/storage/outbox_db.dart';
import 'package:q_pro/core/storage/outbox_sync.dart';
import 'package:q_pro/features/forms/models/form_payload.dart';
import 'package:q_pro/features/forms/models/submission_detail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Offline behaviour the per-unit suites don't reach: the drain loop's own
/// rules (stay put while offline, stay paused after a 401, keep other
/// drafts moving when one is blocked), the upload path's missing-file
/// branch, and the cached-read fallback screens show when a live fetch
/// can't happen.
///
/// Companion to `outbox_db_test.dart` (storage in isolation) and
/// `outbox_sync_test.dart` (one draft's job lifecycle).

SubmissionDetail _fakeSubmission(String name) => SubmissionDetail(
      name: name,
      status: 'Draft',
      project: '',
      stage: '',
      form: const FormPayload(id: '', title: '', version: 1, questions: []),
      answers: const {},
      editable: true,
      permissions: Permissions.none,
      transitions: const [],
      history: const [],
    );

/// Same shape as `outbox_sync_test.dart`'s double: a scripted action per
/// expected call, consumed in order, so retry and pause behaviour is
/// deterministic without waiting out real backoff timers.
class FakeInfriveApi extends InfriveApi {
  FakeInfriveApi() : super(FrappeClient('http://fake.invalid/'));

  final List<SubmissionDetail Function()> _saveQueue = [];
  final List<SubmissionDetail Function()> _submitQueue = [];
  int saveCallCount = 0;
  int submitCallCount = 0;

  void queueSave(SubmissionDetail Function() action) => _saveQueue.add(action);
  void queueSubmit(SubmissionDetail Function() action) =>
      _submitQueue.add(action);

  @override
  Future<SubmissionDetail> saveSubmission({
    required String form,
    String? stage,
    String? submission,
    Map<String, dynamic>? answers,
    String? remarks,
    String? parentSubmission,
  }) async {
    saveCallCount++;
    if (_saveQueue.isEmpty) {
      throw StateError('saveSubmission called with nothing queued');
    }
    return _saveQueue.removeAt(0)();
  }

  @override
  Future<SubmissionDetail> submit(
    String submission, {
    Map<String, dynamic>? answers,
    String? comment,
  }) async {
    submitCallCount++;
    if (_submitQueue.isEmpty) {
      throw StateError('submit called with nothing queued');
    }
    return _submitQueue.removeAt(0)();
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Database db;
  late FakeInfriveApi api;

  /// Submissions the injected uploader was asked to attach a file to —
  /// empty means the engine never attempted an upload at all.
  late List<String> uploadedFor;

  setUp(() async {
    db = await OutboxDatabase.openForTesting(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    OutboxDatabase.instance.setDatabaseForTesting(db);

    isOnline.value = true;
    api = FakeInfriveApi();
    uploadedFor = [];
    OutboxSync.resetForTesting();
    OutboxSync.init(
      api,
      upload: (file, {required String submission}) async {
        uploadedFor.add(submission);
        return '/api/method/infrive_app.api.files.download'
            '?file=abc&filename=${file.uri.pathSegments.last}';
      },
    );
  });

  tearDown(() async {
    isOnline.value = true;
    OutboxDatabase.instance.setDatabaseForTesting(null);
    await db.close();
  });

  group('the queue respects being offline', () {
    test('a drain while offline touches nothing and leaves the job queued',
        () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {'q1': 'written on site'},
      );
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');

      isOnline.value = false;
      await OutboxSync.instance.drainForTesting();

      expect(api.saveCallCount, 0,
          reason: 'no request may go out with no connection');
      expect(
        await OutboxDatabase.instance.jobsForDraft('local-1'),
        hasLength(1),
        reason: 'the job must survive to be sent when the signal returns',
      );
      final draft = await OutboxDatabase.instance.getDraft('local-1');
      expect(draft!['state'], 'local',
          reason: 'being offline is not a data problem — not attention');
      expect(draft['synced_at'], isNull,
          reason: 'nothing reached the server, so nothing is synced');
    });

    test('the same job goes out once the connection is back', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {'q1': 'written on site'},
      );
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');

      isOnline.value = false;
      await OutboxSync.instance.drainForTesting();
      expect(api.saveCallCount, 0);

      isOnline.value = true;
      api.queueSave(() => _fakeSubmission('SUB-00001'));
      await OutboxSync.instance.drainForTesting();

      expect(api.saveCallCount, 1);
      final draft = await OutboxDatabase.instance.getDraft('local-1');
      expect(draft!['server_name'], 'SUB-00001');
      expect(await OutboxDatabase.instance.jobsForDraft('local-1'), isEmpty);
    });
  });

  group('a 401 pauses the whole queue, not just one draft', () {
    test('a second draft is not attempted after the first hits a 401',
        () async {
      for (final id in ['local-1', 'local-2']) {
        await OutboxDatabase.instance.insertDraft(
          localId: id,
          form: 'FORM-1',
          answers: const {},
        );
        await OutboxDatabase.instance.enqueueIfAbsent('save', id);
      }
      api.queueSave(() => throw AuthException('Session expired', 401));

      await OutboxSync.instance.drainForTesting();

      expect(api.saveCallCount, 1,
          reason: 'the session is gone — sending more can only fail again');
      expect(await OutboxDatabase.instance.countPending(), 2,
          reason: 'both drafts must still be waiting for the next sign-in');
    });

    test('the pause outlives the drain that caused it', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
      api.queueSave(() => throw AuthException('Session expired', 401));

      await OutboxSync.instance.drainForTesting();
      expect(api.saveCallCount, 1);

      // A connectivity blip or a fresh enqueue must not retry a session
      // that is known to be dead.
      await OutboxSync.instance.drainForTesting();
      expect(api.saveCallCount, 1,
          reason: 'still paused — no second attempt without a sign-in');
    });

    test('resume() after signing back in sends what was held', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
      api.queueSave(() => throw AuthException('Session expired', 401));

      await OutboxSync.instance.drainForTesting();
      expect(api.saveCallCount, 1);

      api.queueSave(() => _fakeSubmission('SUB-00001'));
      // `resume()` kicks the queue off without returning a future — callers
      // are not meant to block on sync — so wait on the event queue rather
      // than on a drain of our own, which would only race the one it starts.
      OutboxSync.instance.resume();
      await pumpEventQueue();

      expect(api.saveCallCount, 2);
      final draft = await OutboxDatabase.instance.getDraft('local-1');
      expect(draft!['server_name'], 'SUB-00001');
    });
  });

  group('one blocked draft does not hold up the others', () {
    test("a draft waiting on its server name steps aside for another's save",
        () async {
      // local-1's photo cannot go anywhere until local-1 has a server
      // name, and it has no save queued to give it one — so it can never
      // progress this pass. local-2 is ready to go and must not be stuck
      // behind it.
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance
          .enqueueUpload('local-1', 'photo', '/nonexistent/a.jpg');

      await OutboxDatabase.instance.insertDraft(
        localId: 'local-2',
        form: 'FORM-2',
        answers: const {'q1': 'other draft'},
      );
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-2');
      api.queueSave(() => _fakeSubmission('SUB-00002'));

      await OutboxSync.instance.drainForTesting();

      final blocked = await OutboxDatabase.instance.getDraft('local-1');
      expect(blocked!['server_name'], isNull);
      expect(
        await OutboxDatabase.instance.uploadJobsForDraft('local-1'),
        hasLength(1),
        reason: 'the blocked upload stays queued, untouched',
      );
      expect(uploadedFor, isEmpty,
          reason: 'nothing to attach it to yet, so no upload was attempted');

      final moved = await OutboxDatabase.instance.getDraft('local-2');
      expect(moved!['server_name'], 'SUB-00002',
          reason: 'a ready draft must sync even while another is blocked');
      expect(await OutboxDatabase.instance.jobsForDraft('local-2'), isEmpty);
    });

    test('a draft stuck in attention does not block a healthy one', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
      await OutboxDatabase.instance
          .setDraftState('local-1', 'attention', error: 'Missing answer');

      await OutboxDatabase.instance.insertDraft(
        localId: 'local-2',
        form: 'FORM-2',
        answers: const {},
      );
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-2');
      api.queueSave(() => _fakeSubmission('SUB-00002'));

      await OutboxSync.instance.drainForTesting();

      expect(api.saveCallCount, 1,
          reason: 'the attention draft is dropped, not sent');
      expect(await OutboxDatabase.instance.jobsForDraft('local-1'), isEmpty);
      final moved = await OutboxDatabase.instance.getDraft('local-2');
      expect(moved!['server_name'], 'SUB-00002');
    });
  });

  group('a photo whose local file is gone', () {
    test('is dropped rather than retried forever, and the draft still settles',
        () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        serverName: 'SUB-00001',
        form: 'FORM-1',
        answers: const {'q1': 'answered'},
      );
      await OutboxDatabase.instance.enqueueUpload(
        'local-1',
        'photo',
        '${Directory.systemTemp.path}/q-pro-never-written.jpg',
      );

      await OutboxSync.instance.drainForTesting();

      expect(uploadedFor, isEmpty,
          reason: 'there is no file to send — do not call the uploader');
      expect(
        await OutboxDatabase.instance.jobsForDraft('local-1'),
        isEmpty,
        reason: 'an unsendable job must leave the queue, not retry forever',
      );
      final draft = await OutboxDatabase.instance.getDraft('local-1');
      expect(draft!['synced_at'], isNotNull,
          reason: 'the queue drained, so the draft reads as done');
      expect(draft['answers_json'], contains('answered'),
          reason: 'the other answers are left exactly as they were');
    });
  });

  group('cached reads are what a screen falls back to offline', () {
    late InfriveApi reader;

    setUp(() => reader = InfriveApi(FrappeClient('http://fake.invalid/')));

    test('projects come back from cache with nothing on the wire', () async {
      await OutboxDatabase.instance.cachePut('projects', [
        {
          'name': 'PRJ-00001',
          'project_name': 'Imphal Ring Road',
          'project_code': 'IRR',
          'status': 'Active',
          'is_active': 1,
        },
      ]);

      final cached = await reader.cachedProjects();

      expect(cached, hasLength(1));
      expect(cached!.single.projectName, 'Imphal Ring Road');
      expect(cached.single.isActive, isTrue);
    });

    test('an inbox never fetched reads as null, not an empty list', () async {
      expect(await reader.cachedInbox(), isNull,
          reason: 'null means "never loaded" — a screen must not show '
              '"nothing waiting" when it simply does not know');
    });

    test('a stage listing round-trips through the cache', () async {
      await OutboxDatabase.instance.cachePut('stage:STG-1', {
        'id': 'STG-1',
        'name': 'Earthworks',
        'permissions': {
          'Form Submission': {'create': 1, 'view': true},
        },
        'forms': [
          {'id': 'FORM-1', 'title': 'Daily Pour Check', 'status': 'Active'},
        ],
        'submission_counts': {'Draft': 2},
      });

      final cached = await reader.cachedStage('STG-1');

      expect(cached!.name, 'Earthworks');
      expect(cached.forms.single.isActive, isTrue);
      expect(cached.of('Form Submission').can('create'), isTrue);
      expect(cached.submissionCounts['Draft'], 2);
    });

    test('signing out clears the caches a screen would read back', () async {
      await OutboxDatabase.instance.cachePut('projects', [
        {'name': 'PRJ-00001', 'project_name': 'Imphal Ring Road'},
      ]);
      await OutboxDatabase.instance.cachePut('inbox', [
        {'name': 'SUB-00001', 'form': 'FORM-1'},
      ]);
      await OutboxDatabase.instance.cachePut('form:FORM-1', {
        'id': 'FORM-1',
        'title': 'Daily Pour Check',
        'questions': [],
      });

      await OutboxDatabase.instance.clearReadCache();

      expect(await reader.cachedProjects(), isNull);
      expect(await reader.cachedInbox(), isNull);
      expect(
        await OutboxDatabase.instance.cacheGet('form:FORM-1'),
        isNotNull,
        reason: 'question schemas are not permission-filtered — keeping '
            'them lets a signed-back-in device still fill known forms',
      );
    });
  });

  group('the pending count the banner shows', () {
    test('counts every queued job and settles back to zero once drained',
        () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
      await OutboxDatabase.instance.enqueueIfAbsent('submit', 'local-1');

      await OutboxSync.instance.refreshPendingCount();
      expect(OutboxSync.instance.pendingCount.value, 2);

      api.queueSave(() => _fakeSubmission('SUB-00001'));
      api.queueSubmit(() => _fakeSubmission('SUB-00001'));
      await OutboxSync.instance.drainForTesting();

      await OutboxSync.instance.refreshPendingCount();
      expect(OutboxSync.instance.pendingCount.value, 0);
    });

    test('ignores an unsaved scratch fill the user never committed to',
        () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'scratch-1',
        form: 'FORM-1',
        answers: const {'q1': 'half typed'},
        state: OutboxDatabase.scratchState,
      );
      await OutboxDatabase.instance
          .enqueueUpload('scratch-1', 'photo', '/tmp/a.jpg');

      await OutboxSync.instance.refreshPendingCount();

      expect(OutboxSync.instance.pendingCount.value, 0,
          reason: 'a fill that was never saved must not read as '
              '"waiting to sync" in the banner');
    });
  });
}
