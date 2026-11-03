import 'package:flutter/material.dart';

import '../../../core/storage/outbox_db.dart';
import '../../../core/storage/outbox_sync.dart';
import '../../../core/utils/string_formatter.dart';
import '../../forms/presentation/form_fill_page.dart';

// ---------------- DRAFTS / SYNC STATUS SCREEN ----------------

class DraftsPage extends StatefulWidget {
  const DraftsPage({super.key});

  @override
  State<DraftsPage> createState() => _DraftsPageState();
}

class _DraftsPageState extends State<DraftsPage> {
  bool isLoading = true;
  List<Map<String, dynamic>> drafts = [];
  Map<String, List<Map<String, dynamic>>> uploadsByDraft = {};

  /// A draft the queue has finished with. It stays on this screen as a
  /// done receipt — otherwise it would just disappear the moment the
  /// connection came back, with nothing to confirm it went through — and
  /// is removed only when the user clears it.
  bool isSynced(Map<String, dynamic> draft) =>
      draft['synced_at'] != null && draft['state'] != 'attention';

  /// A drained draft that was submitted, not just saved — reopening it
  /// can't submit again, so its card offers View rather than Edit.
  bool isSubmitted(Map<String, dynamic> draft) =>
      isSynced(draft) && draft['state'] == OutboxDatabase.syncedState;

  @override
  void initState() {
    super.initState();
    OutboxSync.instance.pendingCount.addListener(_handleQueueChange);
    fetchDrafts();
  }

  @override
  void dispose() {
    OutboxSync.instance.pendingCount.removeListener(_handleQueueChange);
    super.dispose();
  }

  void _handleQueueChange() {
    if (mounted) fetchDrafts();
  }

  Future<void> fetchDrafts() async {
    setState(() => isLoading = true);
    final all = await OutboxDatabase.instance.getAllDrafts();
    final uploads = <String, List<Map<String, dynamic>>>{};
    for (final draft in all) {
      final localId = draft['local_id'] as String;
      final jobs = await OutboxDatabase.instance.uploadJobsForDraft(localId);
      if (jobs.isNotEmpty) uploads[localId] = jobs;
    }
    if (!mounted) return;
    setState(() {
      drafts = all;
      uploadsByDraft = uploads;
      isLoading = false;
    });
  }

  Future<void> retry(String localId) async {
    await OutboxDatabase.instance.retryDraft(localId);
    OutboxSync.instance.wake();
    fetchDrafts();
  }

  /// Reopens a draft in the form screen. A submitted one opens read only
  /// — hence the card's View label — so this is the handler for both.
  Future<void> edit(String localId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FormFillPage.resume(resumeLocalId: localId),
      ),
    );
    fetchDrafts();
  }

  /// Removes an already-synced draft's local record. Nothing is queued
  /// against it and the server already has it, so there's nothing to
  /// warn about — unlike [discard], which throws away unsent work.
  Future<void> clear(String localId) async {
    await OutboxDatabase.instance.deleteDraftAndJobs(localId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Removed from drafts.')),
    );
    fetchDrafts();
  }

  Future<void> clearAllSynced() async {
    final removed = await OutboxDatabase.instance.clearSyncedDrafts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed == 1 ? '1 synced draft cleared.' : '$removed synced drafts cleared.',
        ),
      ),
    );
    fetchDrafts();
  }

  Future<void> discard(String localId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard draft?'),
        content: const Text(
          "This removes it and anything still queued for it. Can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await OutboxDatabase.instance.deleteDraftAndJobs(localId);
    fetchDrafts();
  }

  Widget buildDraftTile(Map<String, dynamic> draft) {
    final state = draft['state'] as String;
    final localId = draft['local_id'] as String;
    final error = draft['error'] as String?;
    final updatedAt = draft['updated_at'] as int;
    final syncedAt = draft['synced_at'] as int?;
    final synced = isSynced(draft);
    final submitted = isSubmitted(draft);

    final (label, color, icon) = switch (state) {
      'attention' => ('Needs attention', Colors.red, Icons.error_outline),
      _ when submitted => ('Submitted', Colors.green.shade700, Icons.check_circle),
      _ when synced => ('Synced', Colors.green.shade700, Icons.check_circle),
      'syncing' => ('Uploading', Colors.blue, Icons.cloud_upload_outlined),
      _ => ('Waiting to upload', Colors.orange, Icons.schedule),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    draft['form'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  avatar: Icon(icon, size: 18, color: color),
                  label: Text(label),
                  backgroundColor: color.withValues(alpha: 0.15),
                  labelStyle: TextStyle(color: color),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              synced && syncedAt != null
                  ? '$label ${relativeTime(syncedAt)}'
                  : relativeTime(updatedAt),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (error != null && error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => edit(localId),
                  child: Text(submitted ? 'View' : 'Edit'),
                ),
                if (state == 'attention')
                  FilledButton.tonal(
                    onPressed: () => retry(localId),
                    child: const Text('Retry'),
                  ),
                if (synced)
                  OutlinedButton.icon(
                    onPressed: () => clear(localId),
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear'),
                  )
                else
                  OutlinedButton(
                    onPressed: () => discard(localId),
                    child: const Text('Discard'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSynced = drafts.any(isSynced);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drafts'),
        actions: [
          if (hasSynced)
            IconButton(
              tooltip: 'Clear synced',
              onPressed: isLoading ? null : clearAllSynced,
              icon: const Icon(Icons.playlist_remove),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: isLoading ? null : fetchDrafts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : drafts.isEmpty
              ? const Center(child: Text('Nothing queued.'))
              : RefreshIndicator(
                  onRefresh: fetchDrafts,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: drafts.length,
                    itemBuilder: (context, index) => buildDraftTile(drafts[index]),
                  ),
                ),
    );
  }
}
