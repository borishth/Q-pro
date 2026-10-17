import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

import '../network/app_errors.dart';
import '../network/infrive_api.dart';
import '../services/connectivity_service.dart';
import 'outbox_db.dart';

enum _JobOutcome { handled, deferred, paused }

/// Drains the offline outbox (guide section 10) whenever the app is
/// online: `save`, `upload` and `submit` jobs against a draft always run
/// in that order, oldest first. A transient error (network, server 5xx)
/// retries with backoff; a 401 pauses the whole queue until the next
/// sign-in; a 403/417 marks just that draft `attention` and moves on.
///
/// Within one drain pass, a job that can't make progress yet (backoff, or
/// waiting on an earlier job for the same draft) is set aside so jobs for
/// *other* drafts still get a turn — satisfying "different submissions
/// may sync in parallel" without actually firing concurrent requests.
class OutboxSync {
  OutboxSync._(this._api, this._client);

  static OutboxSync? _instance;
  static OutboxSync get instance => _instance!;

  static void init(InfriveApi api, FrappeClient client) {
    _instance ??= OutboxSync._(api, client);
  }

  /// Drops the singleton so the next [init] builds a fresh instance — for
  /// tests only; production code never needs more than one.
  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
  }

  final InfriveApi _api;
  final FrappeClient _client;
  final _db = OutboxDatabase.instance;
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// The outbox row id currently mid-network-call, or null between jobs —
  /// lets the Drafts screen show "uploading now" on the right item instead
  /// of just "waiting" for everything queued.
  final ValueNotifier<int?> activeJobId = ValueNotifier<int?>(null);

  bool _running = false;
  bool _paused = false;
  Timer? _retryTimer;

  static const _backoff = [
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  void start() {
    isOnline.addListener(_onConnectivityChanged);
    refreshPendingCount();
    wake();
  }

  /// Un-pauses the queue (e.g. after a fresh sign-in clears the 401 that
  /// paused it) and tries again.
  void resume() {
    _paused = false;
    wake();
  }

  void _onConnectivityChanged() {
    if (isOnline.value) wake();
  }

  /// Call after enqueueing a job so it's picked up immediately instead of
  /// waiting for the next connectivity change.
  void wake() {
    unawaited(_drain());
  }

  /// Runs exactly one drain pass and waits for it — `wake()` is
  /// fire-and-forget by design (callers shouldn't block on sync), but
  /// tests need a deterministic way to await "the queue has been tried".
  @visibleForTesting
  Future<void> drainForTesting() => _drain();

  Future<void> refreshPendingCount() async {
    pendingCount.value = await _db.countPending();
  }

  Future<void> _drain() async {
    if (_running || _paused || !isOnline.value) return;
    _running = true;
    _retryTimer?.cancel();

    try {
      // Jobs set aside this pass (backoff or blocked on an earlier job for
      // the same draft) so other drafts' jobs still get tried.
      final deferredThisPass = <int>{};

      while (isOnline.value && !_paused) {
        final jobs = (await _db.pendingJobs())
            .where((j) => !deferredThisPass.contains(j['id'] as int))
            .toList();
        await refreshPendingCount();
        if (jobs.isEmpty) return;

        final job = jobs.first;
        final outcome = await _runJob(job);
        if (outcome == _JobOutcome.paused) return;
        if (outcome == _JobOutcome.deferred) {
          deferredThisPass.add(job['id'] as int);
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<_JobOutcome> _runJob(Map<String, dynamic> job) async {
    final id = job['id'] as int;
    final kind = job['kind'] as String;
    final draftLocalId = job['draft_local_id'] as String;
    final attempts = job['attempts'] as int;

    final draft = await _db.getDraft(draftLocalId);
    if (draft == null || draft['state'] == 'attention') {
      await _db.deleteJob(id);
      return _JobOutcome.handled;
    }

    activeJobId.value = id;
    try {
      final answers =
          jsonDecode(draft['answers_json'] as String) as Map<String, dynamic>;
      final serverName = draft['server_name'] as String?;

      switch (kind) {
        case 'save':
          if (serverName == null) {
            // Creating the submission for the first time is the one `save`
            // call that isn't naturally idempotent (a repeat creates a
            // second doc). If `result` is already set, a prior attempt's
            // request succeeded but the app died before recording the
            // name locally — reuse it instead of creating another one.
            final existingResult = job['result'] as String?;
            final resultName = existingResult ??
                (await _api.saveSubmission(
                  form: draft['form'] as String,
                  stage: draft['stage'] as String?,
                  answers: answers,
                ))
                    .name;
            if (existingResult == null) {
              await _db.setJobResult(id, resultName);
            }
            await _db.setDraftServerName(draftLocalId, resultName);
          } else {
            // Updating an already-known submission is a plain overwrite —
            // safe to repeat with no duplication risk.
            await _api.saveSubmission(
              form: draft['form'] as String,
              stage: draft['stage'] as String?,
              submission: serverName,
              answers: answers,
            );
          }

        case 'upload':
          // Needs the draft's server name first — its `save` job (a lower
          // id, so tried earlier this pass) hasn't completed yet.
          if (serverName == null) return _JobOutcome.deferred;

          final payload =
              jsonDecode(job['payload_json'] as String) as Map<String, dynamic>;
          final questionId = payload['questionId'] as String;
          final path = payload['path'] as String;
          final file = File(path);

          final existingUrl = job['result'] as String?;
          String url;
          if (existingUrl != null && existingUrl.isNotEmpty) {
            // Same crash-recovery case as `save`: the file already made
            // it to the server on a prior attempt — don't send it twice.
            url = existingUrl;
          } else {
            if (!await file.exists()) {
              // Local file is gone (e.g. OS reclaimed cache); nothing to
              // retry — drop the job and leave the answer as it was.
              await _db.deleteJob(id);
              return _JobOutcome.handled;
            }

            final uploaded = await _client.attachment.uploadFile(
              file,
              doctype: 'Form Submission',
              docname: serverName,
            );
            final uploadedUrl = uploaded['file_url']?.toString();
            if (uploadedUrl == null || uploadedUrl.isEmpty) {
              throw Exception('Upload did not return a file URL.');
            }
            url = uploadedUrl;
            await _db.setJobResult(id, url);
          }

          final updated = Map<String, dynamic>.from(answers)
            ..[questionId] = url;
          await _db.updateDraftAnswers(draftLocalId, updated);
          await _db.enqueueIfAbsent('save', draftLocalId);
          // The file is on the server now; don't leave a copy behind in
          // local storage.
          unawaited(file.delete().catchError((_) => file));

        case 'submit':
          if (serverName == null) return _JobOutcome.deferred;
          await _api.submit(serverName, answers: answers);
          await _db.setDraftState(draftLocalId, 'synced');
      }

      await _db.deleteJob(id);
      return _JobOutcome.handled;
    } catch (error) {
      if (error is AuthException && error.statusCode == 401) {
        _paused = true;
        return _JobOutcome.paused;
      }
      if (error is AuthException || error is ValidationException) {
        await _db.setDraftState(
          draftLocalId,
          'attention',
          error: describeError(error),
        );
        await _db.deleteJob(id);
        return _JobOutcome.handled;
      }

      await _db.bumpAttempt(id, error.toString());
      final delay = _backoff[attempts.clamp(0, _backoff.length - 1)];
      _retryTimer = Timer(delay, wake);
      return _JobOutcome.deferred;
    } finally {
      if (activeJobId.value == id) activeJobId.value = null;
    }
  }
}
