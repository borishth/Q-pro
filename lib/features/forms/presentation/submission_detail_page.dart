import 'package:flutter/material.dart';

import '../../../core/network/app_errors.dart';
import '../../../core/network/session.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/string_formatter.dart';
import '../models/field_behaviour.dart';
import '../models/history_row.dart';
import '../models/question.dart';
import '../models/submission_detail.dart';
import '../models/transition.dart';

/// A modal comment prompt for a transition (section 12.4's "comment
/// sheet"). Returns null if cancelled, or if [required] and left blank.
Future<String?> askComment(
  BuildContext context,
  String action, {
  required bool required,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(action),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: required ? 'Comment (required)' : 'Comment (optional)',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            if (required && text.isEmpty) return;
            Navigator.of(dialogContext).pop(text);
          },
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

// ---------------- SUBMISSION DETAIL SCREEN ----------------

class SubmissionDetailPage extends StatefulWidget {
  final String submissionName;

  const SubmissionDetailPage({super.key, required this.submissionName});

  @override
  State<SubmissionDetailPage> createState() => _SubmissionDetailPageState();
}

class _SubmissionDetailPageState extends State<SubmissionDetailPage> {
  bool isLoading = true;
  bool isActing = false;
  String? errorMessage;
  SubmissionDetail? submission;

  @override
  void initState() {
    super.initState();
    isOnline.addListener(_handleConnectivityChange);
    fetchSubmission();
  }

  @override
  void dispose() {
    isOnline.removeListener(_handleConnectivityChange);
    super.dispose();
  }

  void _handleConnectivityChange() {
    if (mounted) setState(() {});
  }

  Future<void> fetchSubmission() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loaded = await infrive.getSubmission(widget.submissionName);

      if (!mounted) return;

      setState(() {
        submission = loaded;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (isSessionExpired(error)) {
        signOutToLogin(context);
        return;
      }

      setState(() {
        errorMessage = describeError(error);
        isLoading = false;
      });
    }
  }

  Future<void> runTransition(Transition action) async {
    final current = submission;
    if (current == null) return;

    String? comment;
    if (action.requiresComment) {
      comment = await askComment(context, action.action, required: true);
      if (comment == null || !mounted) return;
    }

    setState(() => isActing = true);

    try {
      final updated = action.permissionAction == 'submit'
          ? await infrive.submit(current.name, comment: comment)
          : await infrive.transition(current.name, action.action, comment: comment);

      if (!mounted) return;

      setState(() {
        submission = updated;
        isActing = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (isSessionExpired(error)) {
        signOutToLogin(context);
        return;
      }

      setState(() => isActing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeError(error))),
      );
    }
  }

  Future<void> deleteSubmission() async {
    final current = submission;
    if (current == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete submission?'),
        content: const Text("This can't be undone."),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await infrive.deleteSubmission(current.name);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      if (isSessionExpired(error)) {
        signOutToLogin(context);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeError(error))),
      );
    }
  }

  Color? _toneColor(String permissionAction) {
    final scheme = Theme.of(context).colorScheme;
    switch (permissionAction) {
      case 'reject':
        return scheme.error;
      case 'approve':
        return scheme.primary;
      default:
        return null;
    }
  }

  Widget buildAnswerRow(Question question, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(formatAnswer(value)),
        ],
      ),
    );
  }

  Widget buildHistoryRow(HistoryRow row) {
    final subtitleParts = [
      if (row.comment != null && row.comment!.isNotEmpty) row.comment!,
      row.by,
      row.time,
    ].where((s) => s.isNotEmpty).join(' · ');

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history, size: 20),
      title: Text(
        row.role != null && row.role!.isNotEmpty
            ? '${row.action} · ${row.role}'
            : row.action,
      ),
      subtitle: Text(subtitleParts),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = submission;

    return Scaffold(
      appBar: AppBar(
        title: Text(current?.form.title ?? widget.submissionName),
        actions: [
          if (current != null && current.editable && current.permissions.can('delete'))
            IconButton(
              tooltip: 'Delete',
              onPressed: deleteSubmission,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: fetchSubmission,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : current == null
                  ? const SizedBox.shrink()
                  : RefreshIndicator(
                      onRefresh: fetchSubmission,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Row(
                            children: [
                              Chip(label: Text(current.status)),
                              const SizedBox(width: 8),
                              if (!current.editable && current.transitions.isEmpty)
                                Expanded(
                                  child: Text(
                                    current.currentRole != null &&
                                            current.currentRole!.isNotEmpty
                                        ? 'Waiting on ${current.currentRole}'
                                        : 'Waiting for action',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Divider(height: 28),
                          for (final question in current.form.questions)
                            if (() {
                              final behaviour = FieldBehaviour.parse(question.rule);
                              return !behaviour.hidden &&
                                  (behaviour.dependsOn.isEmpty ||
                                      dependsMet(behaviour.dependsOn, current.answers));
                            }())
                              buildAnswerRow(question, current.answers[question.id]),
                          if (current.history.isNotEmpty) ...[
                            const Divider(height: 28),
                            const Text(
                              'History',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            for (final row in current.history) buildHistoryRow(row),
                          ],
                        ],
                      ),
                    ),
      bottomNavigationBar: current == null || current.transitions.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: !isOnline.value
                    ? const Text(
                        'Approvals need an internet connection.',
                        textAlign: TextAlign.center,
                      )
                    : isActing
                    ? const Center(
                        child: SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in current.transitions)
                            FilledButton(
                              style: _toneColor(t.permissionAction) != null
                                  ? FilledButton.styleFrom(
                                      backgroundColor: _toneColor(t.permissionAction),
                                    )
                                  : null,
                              onPressed: () => runTransition(t),
                              child: Text(t.action),
                            ),
                        ],
                      ),
              ),
            ),
    );
  }
}
