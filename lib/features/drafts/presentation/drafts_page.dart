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

  Future<void> edit(String localId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FormFillPage.resume(resumeLocalId: localId),
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

    final (label, color) = switch (state) {
      'attention' => ('Needs attention', Colors.red),
      'syncing' => ('Syncing', Colors.blue),
      _ => ('Waiting to sync', Colors.orange),
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
                  label: Text(label),
                  backgroundColor: color.withValues(alpha: 0.15),
                  labelStyle: TextStyle(color: color),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              relativeTime(updatedAt),
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
                  child: const Text('Edit'),
                ),
                if (state == 'attention')
                  FilledButton.tonal(
                    onPressed: () => retry(localId),
                    child: const Text('Retry'),
                  ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drafts'),
        actions: [
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
