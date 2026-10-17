import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

import '../../features/auth/models/me.dart';
import '../../features/forms/models/form_summary.dart';
import '../../features/forms/models/submission_detail.dart';
import '../../features/forms/models/submission_row.dart';
import '../../features/inbox/models/inbox_row.dart';
import '../../features/projects/models/project.dart';
import '../../features/stages/models/hierarchy.dart';
import '../../features/stages/models/stage_dashboard.dart';
import '../storage/outbox_db.dart';

/// Wraps every `infrive_app.api.*` call. Screens call this, never `sdk.api`
/// directly, so the method prefix and the `{"message": ...}` unwrapping only
/// live in one place.
class InfriveApi {
  InfriveApi(this._client);
  final FrappeClient _client;
  static const _prefix = 'infrive_app.api.';

  Map<String, dynamic> _clean(Map<String, dynamic> args) =>
      {for (final e in args.entries) if (e.value != null) e.key: e.value};

  Future<T> _call<T>(
    String method,
    Map<String, dynamic> args, {
    bool get = false,
  }) async {
    final res = await _client.call(
      '$_prefix$method',
      args: _clean(args),
      httpMethod: get ? 'GET' : 'POST',
    );
    final body = res as Map<String, dynamic>;
    return body['message'] as T;
  }

  // ---- session and projects

  Future<Me> me() async =>
      Me.fromJson(await _call('permissions.me', {}, get: true));

  Future<List<Project>> listProjects() async {
    final raw = await _call<List>('projects.list_projects', {}, get: true);
    await OutboxDatabase.instance.cachePut('projects', raw);
    return raw
        .map((e) => Project.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Last successful [listProjects] result, or null if nothing's cached
  /// yet — used to show something while offline instead of just an error.
  Future<List<Project>?> cachedProjects() async {
    final raw = await OutboxDatabase.instance.cacheGet('projects') as List?;
    return raw
        ?.map((e) => Project.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Project> getProject(String project) async => Project.fromJson(
        await _call('projects.get_project', {'project': project}, get: true),
      );

  // ---- hierarchy

  Future<Hierarchy> getHierarchy(String project) async {
    final raw = await _call<Map<String, dynamic>>(
      'hierarchy.get_hierarchy',
      {'project': project},
      get: true,
    );
    await OutboxDatabase.instance.cachePut('hierarchy:$project', raw);
    return Hierarchy.fromJson(raw);
  }

  Future<Hierarchy?> cachedHierarchy(String project) async {
    final raw = await OutboxDatabase.instance.cacheGet('hierarchy:$project')
        as Map<String, dynamic>?;
    return raw == null ? null : Hierarchy.fromJson(raw);
  }

  Future<StageDashboard> getStage(String stage) async {
    final raw = await _call<Map<String, dynamic>>(
      'hierarchy.get_stage',
      {'stage': stage},
      get: true,
    );
    await OutboxDatabase.instance.cachePut('stage:$stage', raw);
    return StageDashboard.fromJson(raw);
  }

  Future<StageDashboard?> cachedStage(String stage) async {
    final raw = await OutboxDatabase.instance.cacheGet('stage:$stage')
        as Map<String, dynamic>?;
    return raw == null ? null : StageDashboard.fromJson(raw);
  }

  // ---- forms

  Future<List<FormSummary>> getStageForms(String project, String stage) async =>
      (await _call<List>(
        'forms.get_stage_forms',
        {'project': project, 'stage': stage},
        get: true,
      ))
          .map((e) => FormSummary.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

  // ---- submissions

  Future<SubmissionDetail> getSubmission(String name) async =>
      SubmissionDetail.fromJson(
        await _call('forms.get_submission', {'submission': name}, get: true),
      );

  /// Used by the link-field picker (a Link question's answer is another
  /// submission's name) and the Stage screen's "Recent Submissions" list.
  Future<List<SubmissionRow>> getSubmissions({
    String? project,
    String? form,
    String? stage,
    String? status,
    int limit = 25,
    int start = 0,
  }) async {
    final raw = await _call<List>('forms.get_submissions', {
      'project': project,
      'form': form,
      'stage': stage,
      'status': status,
      'limit': limit,
      'start': start,
    }, get: true);
    await OutboxDatabase.instance.cachePut(
      'submissions:${project ?? ''}:${form ?? ''}:${stage ?? ''}:${status ?? ''}',
      raw,
    );
    return raw
        .map((e) => SubmissionRow.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<SubmissionRow>?> cachedSubmissions({
    String? project,
    String? form,
    String? stage,
    String? status,
  }) async {
    final raw = await OutboxDatabase.instance.cacheGet(
      'submissions:${project ?? ''}:${form ?? ''}:${stage ?? ''}:${status ?? ''}',
    ) as List?;
    return raw
        ?.map((e) => SubmissionRow.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> deleteSubmission(String submission) =>
      _call('forms.delete_submission', {'submission': submission});

  Future<SubmissionDetail> saveSubmission({
    required String form,
    String? stage,
    String? submission,
    Map<String, dynamic>? answers,
    String? remarks,
    String? parentSubmission,
  }) async =>
      SubmissionDetail.fromJson(await _call('forms.save_submission', {
        'form': form,
        'stage': stage,
        'submission': submission,
        'answers': answers,
        'remarks': remarks,
        'parent_submission': parentSubmission,
      }));

  Future<SubmissionDetail> submit(
    String submission, {
    Map<String, dynamic>? answers,
    String? comment,
  }) async =>
      SubmissionDetail.fromJson(await _call('forms.submit_submission', {
        'submission': submission,
        'answers': answers,
        'comment': comment,
      }));

  // ---- workflow

  Future<List<InboxRow>> inbox() async {
    final raw = await _call<List>('workflow.get_inbox', {}, get: true);
    await OutboxDatabase.instance.cachePut('inbox', raw);
    return raw
        .map((e) => InboxRow.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<InboxRow>?> cachedInbox() async {
    final raw = await OutboxDatabase.instance.cacheGet('inbox') as List?;
    return raw
        ?.map((e) => InboxRow.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<SubmissionDetail> transition(
    String submission,
    String action, {
    String? comment,
  }) async =>
      SubmissionDetail.fromJson(await _call('workflow.transition', {
        'submission': submission,
        'action': action,
        'comment': comment,
      }));
}
