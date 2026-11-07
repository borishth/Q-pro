import 'package:flutter/material.dart';

import '../../../core/network/app_errors.dart';
import '../../../core/network/file_urls.dart';
import '../../../core/network/session.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/string_formatter.dart';
import '../../../core/widgets/attachment_view.dart';
import '../../../core/widgets/state_views.dart';
import '../models/field_behaviour.dart';
import '../models/history_row.dart';
import '../models/question.dart';
import '../models/rating_scale.dart';
import '../models/submission_detail.dart';
import '../models/transition.dart';

/// What the user filled in before a transition runs. [rating] is only ever
/// set for an approval.
class TransitionInput {
  const TransitionInput({this.comment, this.rating});

  final String? comment;
  final int? rating;
}

/// A modal prompt for a transition (section 12.4's "comment sheet"): the
/// comment, plus the mandatory compliance rating when the action is an
/// approval. Returns null if cancelled. Only shown for actions that need
/// something — a plain Submit stays a single tap.
Future<TransitionInput?> askTransitionInput(
  BuildContext context,
  Transition action,
) =>
    showDialog<TransitionInput>(
      context: context,
      builder: (_) => _TransitionPrompt(action: action),
    );

class _TransitionPrompt extends StatefulWidget {
  const _TransitionPrompt({required this.action});

  final Transition action;

  @override
  State<_TransitionPrompt> createState() => _TransitionPromptState();
}

class _TransitionPromptState extends State<_TransitionPrompt> {
  final controller = TextEditingController();
  int? rating;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Both requirements are enforced server-side too; disabling the button
  /// just saves a round trip to be told so.
  bool get canConfirm {
    if (widget.action.requiresRating && rating == null) return false;
    if (widget.action.requiresComment && controller.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  void confirm() {
    final text = controller.text.trim();
    Navigator.of(context).pop(
      TransitionInput(
        comment: text.isEmpty ? null : text,
        rating: rating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(action.action),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (action.requiresRating) ...[
              Text('Compliance rating', style: theme.textTheme.labelLarge),
              _RatingPicker(
                rating: rating,
                onChanged: (value) => setState(() => rating = value),
              ),
              // The hint occupies the same line the label will, so picking
              // a star doesn't shove the comment field down.
              Text(
                ratingLabel(rating) ?? 'Tap a star to rate this submission.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: rating == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: controller,
              // Approvals open on the stars, so don't steal focus to the
              // keyboard and bury them.
              autofocus: !action.requiresRating,
              maxLines: 3,
              // Keeps the confirm button in step with a required comment.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: action.requiresComment
                    ? 'Comment (required)'
                    : 'Comment (optional)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canConfirm ? confirm : null,
          child: Text(action.action),
        ),
      ],
    );
  }
}

/// The 1-5 star picker. Tapping a star selects it; there is no way back to
/// "unrated" because an approval cannot be sent without one.
class _RatingPicker extends StatelessWidget {
  const _RatingPicker({required this.rating, required this.onChanged});

  final int? rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = rating ?? 0;

    return Row(
      children: [
        for (var star = minRating; star <= maxRating; star++)
          IconButton(
            onPressed: () => onChanged(star),
            visualDensity: VisualDensity.compact,
            tooltip: ratingScale[star],
            icon: Icon(
              selected >= star ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 32,
              color: selected >= star ? scheme.primary : scheme.outline,
            ),
          ),
      ],
    );
  }
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
    int? rating;
    if (action.requiresComment || action.requiresRating) {
      final input = await askTransitionInput(context, action);
      if (input == null || !mounted) return;
      comment = input.comment;
      rating = input.rating;
    }

    setState(() => isActing = true);

    try {
      final updated = action.permissionAction == 'submit'
          ? await infrive.submit(current.name, comment: comment)
          : await infrive.transition(
              current.name,
              action.action,
              comment: comment,
              rating: rating,
            );

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
          buildAnswerValue(question, value),
        ],
      ),
    );
  }

  /// Attachment answers are shown as the thing itself — an approver
  /// deciding on a site photo needs to see the photo, not its URL. Every
  /// other type stays plain text.
  Widget buildAnswerValue(Question question, dynamic value) {
    switch (question.type) {
      case 'image':
      case 'signature':
        final urls = fileAnswerUrls(value);
        if (urls.isEmpty) return const Text('—');
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final url in urls) AttachmentImage(url: url)],
        );

      case 'file':
        final urls = fileAnswerUrls(value);
        if (urls.isEmpty) return const Text('—');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final url in urls) AttachmentFileRow(url: url)],
        );

      default:
        return Text(formatAnswer(value));
    }
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.rating > 0)
            _HistoryRating(rating: row.rating, remark: row.ratingRemark),
          Text(subtitleParts),
        ],
      ),
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
              ? ErrorStateView(
                  message: errorMessage!,
                  onRetry: fetchSubmission,
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

/// The rating an approval carried. Shows the remark stored on the action
/// log rather than the local [ratingScale], so a reworded label never
/// rewrites what the approver actually saw.
class _HistoryRating extends StatelessWidget {
  const _HistoryRating({required this.rating, required this.remark});

  final int rating;
  final String? remark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = (remark != null && remark!.isNotEmpty)
        ? remark
        : ratingLabel(rating);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          for (var star = minRating; star <= maxRating; star++)
            Icon(
              rating >= star ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 14,
              color: rating >= star
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          if (label != null) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, style: theme.textTheme.bodySmall),
            ),
          ],
        ],
      ),
    );
  }
}
