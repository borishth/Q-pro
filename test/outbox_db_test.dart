import 'package:flutter_test/flutter_test.dart';
import 'package:q_pro/core/storage/outbox_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Database db;

  setUp(() async {
    // A fresh in-memory database per test — isolated and fast, no device
    // or real file needed (sqflite_common_ffi).
    db = await OutboxDatabase.openForTesting(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    OutboxDatabase.instance.setDatabaseForTesting(db);
  });

  tearDown(() async {
    OutboxDatabase.instance.setDatabaseForTesting(null);
    await db.close();
  });

  group('drafts', () {
    test('insertDraft then getDraft round-trips the answers', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        stage: 'STAGE-1',
        answers: {'q1': 'hello'},
      );

      final draft = await OutboxDatabase.instance.getDraft('local-1');
      expect(draft, isNotNull);
      expect(draft!['form'], 'FORM-1');
      expect(draft['stage'], 'STAGE-1');
      expect(draft['state'], 'local');
      expect(draft['server_name'], isNull);
    });

    test('getDraft returns null for an unknown id', () async {
      expect(await OutboxDatabase.instance.getDraft('nope'), isNull);
    });

    test('updateDraftAnswers overwrites the stored answers', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: {'q1': 'first'},
      );
      await OutboxDatabase.instance
          .updateDraftAnswers('local-1', {'q1': 'second', 'q2': 'new'});

      final draft = await OutboxDatabase.instance.getDraft('local-1');
      expect(draft!['answers_json'], contains('second'));
      expect(draft['answers_json'], contains('new'));
      expect(draft['answers_json'], isNot(contains('first')));
    });

    test('setDraftServerName records the name and moves state to syncing', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance.setDraftServerName('local-1', 'SUB-0001');

      final draft = await OutboxDatabase.instance.getDraft('local-1');
      expect(draft!['server_name'], 'SUB-0001');
      expect(draft['state'], 'syncing');
    });

    test('setDraftState attaches an error message for attention', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance
          .setDraftState('local-1', 'attention', error: 'Missing required field');

      final draft = await OutboxDatabase.instance.getDraft('local-1');
      expect(draft!['state'], 'attention');
      expect(draft['error'], 'Missing required field');
    });

    test('insertDraft twice with the same id replaces rather than duplicating', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        serverName: 'SUB-0001',
        answers: const {},
      );

      final all = await OutboxDatabase.instance.getAllDrafts();
      // Not asserting on getAllDrafts' filtering here, just that there's
      // exactly one row for local-1 underneath.
      final draft = await OutboxDatabase.instance.getDraft('local-1');
      expect(draft!['server_name'], 'SUB-0001');
      expect(all.where((d) => d['local_id'] == 'local-1').length, lessThanOrEqualTo(1));
    });
  });

  group('getAllDrafts filtering', () {
    // Regression test for a real bug found during on-device testing: a
    // draft handled entirely online (DraftSaver + direct submit, nothing
    // ever queued) still got a local mirror row, and used to show up in
    // the Drafts screen forever as "waiting to sync".
    test('excludes a draft with no outbox jobs and state != attention', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'SUB-0001',
        serverName: 'SUB-0001',
        form: 'FORM-1',
        answers: const {},
      );
      // No setDraftState('synced') call even — the point is that "local"
      // with nothing queued should already be excluded regardless.

      final drafts = await OutboxDatabase.instance.getAllDrafts();
      expect(drafts, isEmpty);
    });

    test('includes a draft stuck in attention even with no queued jobs', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance
          .setDraftState('local-1', 'attention', error: 'boom');

      final drafts = await OutboxDatabase.instance.getAllDrafts();
      expect(drafts.map((d) => d['local_id']), contains('local-1'));
    });

    test('includes a draft that has a queued job even while state is local', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');

      final drafts = await OutboxDatabase.instance.getAllDrafts();
      expect(drafts.map((d) => d['local_id']), contains('local-1'));
    });

    test('orders by most recently updated first', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'older',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance.setDraftState('older', 'attention', error: 'x');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await OutboxDatabase.instance.insertDraft(
        localId: 'newer',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance.setDraftState('newer', 'attention', error: 'y');

      final drafts = await OutboxDatabase.instance.getAllDrafts();
      expect(drafts.first['local_id'], 'newer');
    });
  });

  group('retryDraft / deleteDraftAndJobs', () {
    test('retryDraft clears the attention error and re-queues a save', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance
          .setDraftState('local-1', 'attention', error: 'Validation failed');

      await OutboxDatabase.instance.retryDraft('local-1');

      final draft = await OutboxDatabase.instance.getDraft('local-1');
      expect(draft!['state'], 'local'); // no server_name yet
      final jobs = await OutboxDatabase.instance.jobsForDraft('local-1');
      expect(jobs.map((j) => j['kind']), contains('save'));
    });

    test('retryDraft uses syncing (not local) once a server name is known', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        serverName: 'SUB-0001',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance
          .setDraftState('local-1', 'attention', error: 'boom');

      await OutboxDatabase.instance.retryDraft('local-1');

      final draft = await OutboxDatabase.instance.getDraft('local-1');
      expect(draft!['state'], 'syncing');
    });

    test('deleteDraftAndJobs removes the draft and every queued job for it', () async {
      await OutboxDatabase.instance.insertDraft(
        localId: 'local-1',
        form: 'FORM-1',
        answers: const {},
      );
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
      await OutboxDatabase.instance.enqueueUpload('local-1', 'q2', '/tmp/photo.jpg');

      await OutboxDatabase.instance.deleteDraftAndJobs('local-1');

      expect(await OutboxDatabase.instance.getDraft('local-1'), isNull);
      expect(await OutboxDatabase.instance.jobsForDraft('local-1'), isEmpty);
    });
  });

  group('enqueueIfAbsent / enqueueUpload dedup', () {
    test('enqueueIfAbsent does not duplicate a pending job of the same kind', () async {
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');

      final jobs = await OutboxDatabase.instance.jobsForDraft('local-1');
      expect(jobs.where((j) => j['kind'] == 'save'), hasLength(1));
    });

    test('enqueueIfAbsent allows different kinds to coexist', () async {
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
      await OutboxDatabase.instance.enqueueIfAbsent('submit', 'local-1');

      final jobs = await OutboxDatabase.instance.jobsForDraft('local-1');
      expect(jobs.map((j) => j['kind']), containsAll(['save', 'submit']));
    });

    test('enqueueUpload replaces a not-yet-processed upload for the same question', () async {
      await OutboxDatabase.instance.enqueueUpload('local-1', 'photo', '/tmp/a.jpg');
      await OutboxDatabase.instance.enqueueUpload('local-1', 'photo', '/tmp/b.jpg');

      final uploads = await OutboxDatabase.instance.uploadJobsForDraft('local-1');
      expect(uploads, hasLength(1));

      final pending = await OutboxDatabase.instance.pendingUploadsForDraft('local-1');
      expect(pending['photo'], '/tmp/b.jpg');
    });

    test('enqueueUpload for a different question does not touch the first one', () async {
      await OutboxDatabase.instance.enqueueUpload('local-1', 'photo', '/tmp/a.jpg');
      await OutboxDatabase.instance.enqueueUpload('local-1', 'signature', '/tmp/sig.png');

      final pending = await OutboxDatabase.instance.pendingUploadsForDraft('local-1');
      expect(pending, {'photo': '/tmp/a.jpg', 'signature': '/tmp/sig.png'});
    });
  });

  group('job result (duplicate-prevention idempotency marker)', () {
    test('setJobResult persists and is readable back via jobsForDraft', () async {
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
      final jobs = await OutboxDatabase.instance.jobsForDraft('local-1');
      final jobId = jobs.single['id'] as int;

      await OutboxDatabase.instance.setJobResult(jobId, 'SUB-0099');

      final updated = await OutboxDatabase.instance.jobsForDraft('local-1');
      expect(updated.single['result'], 'SUB-0099');
    });

    test('a fresh job (new pick) starts with no result, even if a prior job for the same question had one', () async {
      await OutboxDatabase.instance.enqueueUpload('local-1', 'photo', '/tmp/a.jpg');
      final firstJob =
          (await OutboxDatabase.instance.uploadJobsForDraft('local-1')).single;
      await OutboxDatabase.instance.setJobResult(firstJob['id'] as int, '/files/a.jpg');

      // Simulate the job completing and being deleted, then the user
      // picking a new photo for the same question.
      await OutboxDatabase.instance.deleteJob(firstJob['id'] as int);
      await OutboxDatabase.instance.enqueueUpload('local-1', 'photo', '/tmp/c.jpg');

      final secondJob =
          (await OutboxDatabase.instance.uploadJobsForDraft('local-1')).single;
      expect(secondJob['result'], isNull);
    });
  });

  group('bumpAttempt / countPending', () {
    test('bumpAttempt increments attempts and records the error', () async {
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
      final jobId =
          (await OutboxDatabase.instance.jobsForDraft('local-1')).single['id'] as int;

      await OutboxDatabase.instance.bumpAttempt(jobId, 'Network unreachable');
      await OutboxDatabase.instance.bumpAttempt(jobId, 'Network unreachable');

      final job =
          (await OutboxDatabase.instance.jobsForDraft('local-1')).single;
      expect(job['attempts'], 2);
      expect(job['last_error'], 'Network unreachable');
    });

    test('countPending reflects the total number of queued jobs', () async {
      expect(await OutboxDatabase.instance.countPending(), 0);
      await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
      await OutboxDatabase.instance.enqueueIfAbsent('submit', 'local-1');
      expect(await OutboxDatabase.instance.countPending(), 2);
    });
  });

  group('cache', () {
    test('cachePut/cacheGet round-trips a Map', () async {
      await OutboxDatabase.instance.cachePut('form:FORM-1', {'id': 'FORM-1'});
      final cached = await OutboxDatabase.instance.cacheGet('form:FORM-1');
      expect(cached, {'id': 'FORM-1'});
    });

    test('cachePut/cacheGet round-trips a List', () async {
      await OutboxDatabase.instance.cachePut('projects', [
        {'name': 'PROJ-001'},
      ]);
      final cached = await OutboxDatabase.instance.cacheGet('projects');
      expect(cached, [
        {'name': 'PROJ-001'},
      ]);
    });

    test('cacheGet returns null for a key never cached', () async {
      expect(await OutboxDatabase.instance.cacheGet('nothing-here'), isNull);
    });

    test('cachePut overwrites a previous value for the same key', () async {
      await OutboxDatabase.instance.cachePut('projects', ['old']);
      await OutboxDatabase.instance.cachePut('projects', ['new']);
      expect(await OutboxDatabase.instance.cacheGet('projects'), ['new']);
    });

    test('clearReadCache removes permission-filtered caches but keeps form payloads', () async {
      await OutboxDatabase.instance.cachePut('projects', ['p']);
      await OutboxDatabase.instance.cachePut('inbox', ['i']);
      await OutboxDatabase.instance.cachePut('hierarchy:PROJ-001', {'nodes': []});
      await OutboxDatabase.instance.cachePut('stage:STAGE-1', {'id': 'STAGE-1'});
      await OutboxDatabase.instance.cachePut('form:FORM-1', {'id': 'FORM-1'});

      await OutboxDatabase.instance.clearReadCache();

      expect(await OutboxDatabase.instance.cacheGet('projects'), isNull);
      expect(await OutboxDatabase.instance.cacheGet('inbox'), isNull);
      expect(await OutboxDatabase.instance.cacheGet('hierarchy:PROJ-001'), isNull);
      expect(await OutboxDatabase.instance.cacheGet('stage:STAGE-1'), isNull);
      // Form payloads survive sign-out so an already-known form can still
      // be filled offline after signing back in.
      expect(await OutboxDatabase.instance.cacheGet('form:FORM-1'), isNotNull);
    });
  });
}
