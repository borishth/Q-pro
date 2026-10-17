import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite outbox for offline writes (Flutter API Guide section 10).
/// The Frappe mobile SDK's own sync targets doctypes; Infrive's API is
/// custom RPCs, so the app keeps this small outbox instead of using
/// `sdk.sync`/`sdk.repository`.
///
/// `drafts` holds the latest known answers for a submission the user is
/// filling, keyed by a locally-generated id until the server assigns a
/// real name. `outbox` holds pending `save`/`upload`/`submit` jobs against
/// a draft, oldest first — `upload` jobs carry a `payload_json` with the
/// question id and the local file path to send. `cache` holds each form's
/// question payload and the last successful list/detail responses the
/// user has seen, so the app has something to show offline.
class OutboxDatabase {
  OutboxDatabase._();
  static final OutboxDatabase instance = OutboxDatabase._();

  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = await getDatabasesPath();
    return openDatabase(
      '$path/q_pro_outbox.db',
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE drafts (
        local_id TEXT PRIMARY KEY,
        server_name TEXT,
        form TEXT NOT NULL,
        stage TEXT,
        answers_json TEXT NOT NULL,
        state TEXT NOT NULL,
        error TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        draft_local_id TEXT NOT NULL,
        payload_json TEXT,
        result TEXT,
        created_at INTEGER NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE cache (
        key TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        fetched_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE outbox ADD COLUMN payload_json TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE outbox ADD COLUMN result TEXT');
    }
  }

  /// Opens a database with this class's exact schema via [factory] at
  /// [path] — for tests to get an isolated (typically in-memory) instance
  /// with `sqflite_common_ffi` instead of the real on-device one. Not used
  /// by production code.
  @visibleForTesting
  static Future<Database> openForTesting(
    DatabaseFactory factory,
    String path,
  ) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// Points this singleton at [db] instead of the real device database —
  /// for tests. Pass null to release it (e.g. in `tearDown`).
  @visibleForTesting
  void setDatabaseForTesting(Database? db) {
    _db = db;
  }

  // ---- drafts

  Future<void> insertDraft({
    required String localId,
    String? serverName,
    required String form,
    String? stage,
    required Map<String, dynamic> answers,
  }) async {
    final db = await _database;
    await db.insert('drafts', {
      'local_id': localId,
      'server_name': serverName,
      'form': form,
      'stage': stage,
      'answers_json': jsonEncode(answers),
      'state': 'local',
      'error': null,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getDraft(String localId) async {
    final db = await _database;
    final rows =
        await db.query('drafts', where: 'local_id = ?', whereArgs: [localId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateDraftAnswers(
    String localId,
    Map<String, dynamic> answers,
  ) async {
    final db = await _database;
    await db.update(
      'drafts',
      {
        'answers_json': jsonEncode(answers),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> setDraftServerName(String localId, String serverName) async {
    final db = await _database;
    await db.update(
      'drafts',
      {'server_name': serverName, 'state': 'syncing'},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> setDraftState(
    String localId,
    String state, {
    String? error,
  }) async {
    final db = await _database;
    await db.update(
      'drafts',
      {'state': state, 'error': error},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Drafts that actually need the Drafts screen's attention: either
  /// stuck (`attention`) or still have a job queued against them.
  ///
  /// Every draft gets a local mirror row the moment it's created — even
  /// one that's fully handled online via the direct `DraftSaver`/`submit`
  /// path and never touches the outbox — so filtering on `state` alone
  /// would wrongly list already-synced online drafts as "waiting to
  /// sync" forever. Requiring either `attention` or a live outbox row
  /// is what actually means "this needs the user to look at it."
  Future<List<Map<String, dynamic>>> getAllDrafts() async {
    final db = await _database;
    return db.rawQuery('''
      SELECT DISTINCT d.* FROM drafts d
      WHERE d.state = 'attention'
         OR EXISTS (SELECT 1 FROM outbox o WHERE o.draft_local_id = d.local_id)
      ORDER BY d.updated_at DESC
    ''');
  }

  /// Clears a draft's `attention` error and re-queues a `save` so it's
  /// tried again (e.g. after a transient validation problem was fixed
  /// server-side, or the user just wants another attempt).
  Future<void> retryDraft(String localId) async {
    final draft = await getDraft(localId);
    if (draft == null) return;
    await setDraftState(
      localId,
      draft['server_name'] == null ? 'local' : 'syncing',
    );
    await enqueueIfAbsent('save', localId);
  }

  /// Permanently discards a draft and any jobs still queued against it —
  /// does not delete anything already synced to the server.
  Future<void> deleteDraftAndJobs(String localId) async {
    final db = await _database;
    await db.delete('outbox', where: 'draft_local_id = ?', whereArgs: [localId]);
    await db.delete('drafts', where: 'local_id = ?', whereArgs: [localId]);
  }

  // ---- outbox

  /// Queues [kind] (`save` or `submit`) for [draftLocalId] unless a job of
  /// that kind is already pending for it, so repeated edits don't pile up
  /// duplicate jobs.
  Future<void> enqueueIfAbsent(String kind, String draftLocalId) async {
    final db = await _database;
    final existing = await db.query(
      'outbox',
      where: 'kind = ? AND draft_local_id = ?',
      whereArgs: [kind, draftLocalId],
    );
    if (existing.isNotEmpty) return;
    await db.insert('outbox', {
      'kind': kind,
      'draft_local_id': draftLocalId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
      'last_error': null,
    });
  }

  /// Queues an `upload` job for [questionId] on [draftLocalId], replacing
  /// any not-yet-processed upload already queued for that question (e.g.
  /// the user picked a different photo before the first one synced).
  Future<void> enqueueUpload(
    String draftLocalId,
    String questionId,
    String path,
  ) async {
    final db = await _database;
    await db.delete(
      'outbox',
      where: "kind = 'upload' AND draft_local_id = ? AND payload_json LIKE ?",
      whereArgs: [draftLocalId, '%"questionId":"$questionId"%'],
    );
    await db.insert('outbox', {
      'kind': 'upload',
      'draft_local_id': draftLocalId,
      'payload_json': jsonEncode({'questionId': questionId, 'path': path}),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
      'last_error': null,
    });
  }

  Future<List<Map<String, dynamic>>> pendingJobs() async {
    final db = await _database;
    return db.query('outbox', orderBy: 'id ASC');
  }

  /// questionId -> local file path for every not-yet-processed `upload`
  /// job on [draftLocalId] — used to restore the "picked but not yet
  /// uploaded" preview when a draft is reopened for editing.
  Future<Map<String, String>> pendingUploadsForDraft(String draftLocalId) async {
    final db = await _database;
    final rows = await db.query(
      'outbox',
      where: "kind = 'upload' AND draft_local_id = ?",
      whereArgs: [draftLocalId],
    );
    final result = <String, String>{};
    for (final row in rows) {
      final payloadJson = row['payload_json'] as String?;
      if (payloadJson == null) continue;
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      result[payload['questionId'] as String] = payload['path'] as String;
    }
    return result;
  }

  /// Jobs currently queued against [draftLocalId], oldest first — for the
  /// Drafts screen's per-file waiting/uploading/retrying breakdown.
  Future<List<Map<String, dynamic>>> jobsForDraft(String draftLocalId) async {
    final db = await _database;
    return db.query(
      'outbox',
      where: 'draft_local_id = ?',
      whereArgs: [draftLocalId],
      orderBy: 'id ASC',
    );
  }

  /// `upload` jobs currently queued against [draftLocalId] — the
  /// Drafts screen's per-file waiting/uploading/retrying breakdown.
  Future<List<Map<String, dynamic>>> uploadJobsForDraft(
    String draftLocalId,
  ) async {
    final db = await _database;
    return db.query(
      'outbox',
      where: "kind = 'upload' AND draft_local_id = ?",
      whereArgs: [draftLocalId],
      orderBy: 'id ASC',
    );
  }

  Future<void> deleteJob(int id) async {
    final db = await _database;
    await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  /// Records what a job actually produced (a new submission name for
  /// `save`, a file URL for `upload`) *before* the caller touches the
  /// `drafts` row or deletes the job. If the app is killed between the
  /// server confirming success and that bookkeeping finishing, the next
  /// launch sees this already set and skips repeating the network call
  /// — the fix for retries creating duplicate files or submissions.
  Future<void> setJobResult(int id, String result) async {
    final db = await _database;
    await db.update(
      'outbox',
      {'result': result},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> bumpAttempt(int id, String error) async {
    final db = await _database;
    await db.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  Future<int> countPending() async {
    final db = await _database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM outbox');
    return (result.first['c'] as int?) ?? 0;
  }

  // ---- generic JSON cache (form payloads, and last-seen list/detail
  // responses so a read has something to fall back to while offline)

  Future<void> cachePut(String key, Object json) async {
    final db = await _database;
    await db.insert(
      'cache',
      {
        'key': key,
        'json': jsonEncode(json),
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns the decoded JSON for [key] — a `Map` or a `List` depending on
  /// what was cached — or null if nothing has been cached yet.
  Future<dynamic> cacheGet(String key) async {
    final db = await _database;
    final rows = await db.query('cache', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['json'] as String);
  }

  /// Clears the permission-filtered read caches on sign-out or user
  /// change (guide section 12.6): projects, hierarchy, stage, submission
  /// and inbox entries. Form-payload caches (`form:<id>`) are left alone
  /// — they're just question schemas, not permission-filtered, and
  /// keeping them lets the device still fill known forms offline after
  /// signing back in.
  Future<void> clearReadCache() async {
    final db = await _database;
    await db.delete(
      'cache',
      where: "key = 'projects' OR key = 'inbox' OR key LIKE 'hierarchy:%' "
          "OR key LIKE 'stage:%' OR key LIKE 'submission:%' OR key LIKE 'submissions:%'",
    );
  }
}
