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

/// A minimal double for a server response — only what the sync engine
/// itself reads (`.name`) matters for these tests.
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

/// Stands in for the real network calls `OutboxSync` makes through
/// `InfriveApi`. Each queue holds one action per expected call, consumed
/// in order, so a test can script e.g. "first call fails, second
/// succeeds" to exercise retry behaviour deterministically and without
/// waiting out the real backoff timers.
class FakeInfriveApi extends InfriveApi {
  FakeInfriveApi() : super(FrappeClient('http://fake.invalid/'));

  final List<SubmissionDetail Function()> _saveQueue = [];
  final List<SubmissionDetail Function()> _submitQueue = [];
  int saveCallCount = 0;
  int submitCallCount = 0;
  final List<String?> saveSubmissionArg = [];

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
    saveSubmissionArg.add(submission);
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

  setUp(() async {
    db = await OutboxDatabase.openForTesting(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    OutboxDatabase.instance.setDatabaseForTesting(db);

    isOnline.value = true;
    api = FakeInfriveApi();
    OutboxSync.resetForTesting();
    OutboxSync.init(api);
  });

  tearDown(() async {
    OutboxDatabase.instance.setDatabaseForTesting(null);
    await db.close();
  });

  test('a successful save records the server name and clears the job', () async {
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      form: 'FORM-1',
      answers: {'q1': 'hi'},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
    api.queueSave(() => _fakeSubmission('SUB-0001'));

    await OutboxSync.instance.drainForTesting();

    final draft = await OutboxDatabase.instance.getDraft('local-1');
    expect(draft!['server_name'], 'SUB-0001');
    expect(await OutboxDatabase.instance.jobsForDraft('local-1'), isEmpty);
    expect(api.saveCallCount, 1);
  });

  test('a network failure keeps the job queued and counts the attempt, without creating anything', () async {
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      form: 'FORM-1',
      answers: const {},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
    api.queueSave(() => throw NetworkException('offline'));

    await OutboxSync.instance.drainForTesting();

    final draft = await OutboxDatabase.instance.getDraft('local-1');
    expect(draft!['server_name'], isNull, reason: 'no submission should exist after a failed attempt');
    final jobs = await OutboxDatabase.instance.jobsForDraft('local-1');
    expect(jobs, hasLength(1), reason: 'the job must survive to be retried');
    expect(jobs.single['attempts'], 1);
    expect(api.saveCallCount, 1);
  });

  test('retrying after a transient failure succeeds without double-calling once recovered', () async {
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      form: 'FORM-1',
      answers: const {},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');

    api.queueSave(() => throw NetworkException('offline'));
    await OutboxSync.instance.drainForTesting(); // fails, job stays queued

    // The real app would wait for the backoff timer; tests fire the next
    // attempt directly instead of sleeping through real delays.
    api.queueSave(() => _fakeSubmission('SUB-0002'));
    await OutboxSync.instance.drainForTesting(); // retry succeeds

    final draft = await OutboxDatabase.instance.getDraft('local-1');
    expect(draft!['server_name'], 'SUB-0002');
    expect(await OutboxDatabase.instance.jobsForDraft('local-1'), isEmpty);
    expect(api.saveCallCount, 2);
  });

  test('a job already carrying a result (prior success, crash before cleanup) is never resent', () async {
    // Simulates: the server already created the submission, but the app
    // died before `setDraftServerName` ran — the fix for retries creating
    // duplicate submissions.
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      form: 'FORM-1',
      answers: const {},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
    final jobId =
        (await OutboxDatabase.instance.jobsForDraft('local-1')).single['id'] as int;
    await OutboxDatabase.instance.setJobResult(jobId, 'SUB-ALREADY-CREATED');
    // Deliberately nothing queued on `api` — a network call here would
    // throw StateError and fail the test.

    await OutboxSync.instance.drainForTesting();

    final draft = await OutboxDatabase.instance.getDraft('local-1');
    expect(draft!['server_name'], 'SUB-ALREADY-CREATED');
    expect(api.saveCallCount, 0, reason: 'must not create a second submission');
    expect(await OutboxDatabase.instance.jobsForDraft('local-1'), isEmpty);
  });

  test('updating an already-known submission is called again freely (no duplication risk)', () async {
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      serverName: 'SUB-0001',
      form: 'FORM-1',
      answers: {'q1': 'updated'},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
    api.queueSave(() => _fakeSubmission('SUB-0001'));

    await OutboxSync.instance.drainForTesting();

    expect(api.saveSubmissionArg, ['SUB-0001']);
    expect(await OutboxDatabase.instance.jobsForDraft('local-1'), isEmpty);
  });

  test('a validation error marks the draft attention and drops the job (no infinite retry)', () async {
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      form: 'FORM-1',
      answers: const {},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
    api.queueSave(() => throw ValidationException('A required field is missing'));

    await OutboxSync.instance.drainForTesting();

    final draft = await OutboxDatabase.instance.getDraft('local-1');
    expect(draft!['state'], 'attention');
    expect(draft['error'], contains('required field'));
    expect(await OutboxDatabase.instance.jobsForDraft('local-1'), isEmpty);
  });

  test('a 401 leaves the job queued untouched rather than treating it as a data problem', () async {
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      form: 'FORM-1',
      answers: const {},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
    api.queueSave(() => throw AuthException('Session expired', 401));

    await OutboxSync.instance.drainForTesting();

    final draft = await OutboxDatabase.instance.getDraft('local-1');
    expect(draft!['state'], isNot('attention'));
    final jobs = await OutboxDatabase.instance.jobsForDraft('local-1');
    expect(jobs, hasLength(1), reason: 'the job must still be there to retry after sign-in');
  });

  test('submit marks the draft synced and clears the job', () async {
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      serverName: 'SUB-0001',
      form: 'FORM-1',
      answers: {'q1': 'final answer'},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('submit', 'local-1');
    api.queueSubmit(() => _fakeSubmission('SUB-0001'));

    await OutboxSync.instance.drainForTesting();

    final draft = await OutboxDatabase.instance.getDraft('local-1');
    expect(draft!['state'], 'synced');
    expect(await OutboxDatabase.instance.jobsForDraft('local-1'), isEmpty);
  });

  test('an upload job waits for its draft to have a server name before doing anything', () async {
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      form: 'FORM-1',
      answers: const {},
    );
    await OutboxDatabase.instance.enqueueUpload('local-1', 'photo', '/tmp/a.jpg');
    // No fake HTTP upload is wired up here — if the engine tried to upload
    // before the save completed, this test would hang or throw.

    await OutboxSync.instance.drainForTesting();

    final jobs = await OutboxDatabase.instance.uploadJobsForDraft('local-1');
    expect(jobs, hasLength(1), reason: 'upload must stay queued until save gives it a server name');
  });

  test('an upload is attached to the submission the server named', () async {
    // The whole point of owning the upload call instead of using the
    // SDK's: the file has to arrive tied to its Form Submission, or
    // `files.download` has nothing to authorize and refuses everyone but
    // the uploader — an approver then sees a broken image.
    final file = File('${Directory.systemTemp.path}/outbox-upload-test.jpg');
    await file.writeAsBytes(const [1, 2, 3]);
    addTearDown(() => file.existsSync() ? file.deleteSync() : null);

    String? gotSubmission;
    OutboxSync.resetForTesting();
    OutboxSync.init(
      api,
      upload: (f, {required String submission}) async {
        gotSubmission = submission;
        return '/api/method/infrive_app.api.files.download?file=abc&filename=a.jpg';
      },
    );

    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      form: 'FORM-1',
      answers: const {},
    );
    api.queueSave(() => _fakeSubmission('SUB-00100'));
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
    await OutboxDatabase.instance.enqueueUpload('local-1', 'photo', file.path);
    api.queueSave(() => _fakeSubmission('SUB-00100'));

    await OutboxSync.instance.drainForTesting();

    expect(gotSubmission, 'SUB-00100');
    final draft = await OutboxDatabase.instance.getDraft('local-1');
    expect(
      (draft!['answers_json'] as String).contains('files.download'),
      isTrue,
      reason: 'the returned file_url must land in the answer',
    );
  });

  test('a drained queue stamps the draft as synced so it stays listed as done', () async {
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      form: 'FORM-1',
      answers: const {},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
    api.queueSave(() => _fakeSubmission('SUB-0001'));

    await OutboxSync.instance.drainForTesting();

    final draft = await OutboxDatabase.instance.getDraft('local-1');
    expect(draft!['synced_at'], isNotNull);
    // Saved, not submitted — the state must not claim otherwise.
    expect(draft['state'], isNot(OutboxDatabase.syncedState));
    expect(
      (await OutboxDatabase.instance.getAllDrafts()).map((d) => d['local_id']),
      contains('local-1'),
      reason: 'a finished draft stays on the Drafts screen until cleared',
    );
  });

  test('a draft is only stamped synced once its last job drains', () async {
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      form: 'FORM-1',
      answers: const {},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
    await OutboxDatabase.instance.enqueueIfAbsent('submit', 'local-1');
    api.queueSave(() => _fakeSubmission('SUB-0001'));
    api.queueSubmit(() => throw NetworkException('offline'));

    await OutboxSync.instance.drainForTesting();

    final draft = await OutboxDatabase.instance.getDraft('local-1');
    expect(draft!['synced_at'], isNull,
        reason: 'the submit is still queued, so nothing is done yet');
  });

  test('a failed job after a drain clears the synced stamp again', () async {
    await OutboxDatabase.instance.insertDraft(
      localId: 'local-1',
      serverName: 'SUB-0001',
      form: 'FORM-1',
      answers: const {},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'local-1');
    api.queueSave(() => _fakeSubmission('SUB-0001'));
    await OutboxSync.instance.drainForTesting();
    expect((await OutboxDatabase.instance.getDraft('local-1'))!['synced_at'],
        isNotNull);

    // The user edits the draft again, putting fresh work on the queue.
    await OutboxDatabase.instance.enqueueIfAbsent('submit', 'local-1');

    final draft = await OutboxDatabase.instance.getDraft('local-1');
    expect(draft!['synced_at'], isNull,
        reason: 'queueing new work makes the draft pending again');
  });

  test('a missing draft (discarded mid-flight) just drops its orphaned job', () async {
    await OutboxDatabase.instance.enqueueIfAbsent('save', 'does-not-exist');

    await OutboxSync.instance.drainForTesting();

    expect(await OutboxDatabase.instance.jobsForDraft('does-not-exist'), isEmpty);
    expect(api.saveCallCount, 0);
  });
}
