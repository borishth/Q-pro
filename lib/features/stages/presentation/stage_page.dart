import 'package:flutter/material.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/app_errors.dart';
import '../../../core/network/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_nav_bar.dart';
import '../../../core/widgets/cached_data_banner.dart';
import '../../../core/widgets/scale_button.dart';
import '../../forms/models/form_summary.dart';
import '../../forms/presentation/form_fill_page.dart';
import '../../forms/presentation/form_submissions_page.dart';
import '../models/hierarchy.dart';
import '../models/stage_dashboard.dart';
import 'stage_folder_card.dart';

// ---------------- STAGE SCREEN ----------------

/// The accent color every "this is a form, not a folder" element uses
/// across the app — matches the Dashboard's Forms quick-action tile.
const _formAccent = Color(0xFF7C3AED);

/// One stage's own content (forms, if [canAccessOwnContent]) *and* its
/// sub-phases (if any) on the same screen — tapping a sub-phase recurses
/// into a fresh instance of this same page, matching how a real folder
/// tree is browsed one level at a time. Each form is its own expandable
/// card (see [_FormCard]) with separate "start a new one" / "view history"
/// actions, rather than one flat list mixing every form's submissions.
class StagePage extends StatefulWidget {
  final String stageId;
  final String stageName;
  final List<StageNode> children;

  /// False for a `contextOnly` organisational node with no view permission
  /// of its own — still drillable for its reachable descendants' sake, but
  /// its own forms are skipped rather than fetched (which would just 403).
  final bool canAccessOwnContent;

  const StagePage({
    super.key,
    required this.stageId,
    required this.stageName,
    this.children = const [],
    this.canAccessOwnContent = true,
  });

  @override
  State<StagePage> createState() => _StagePageState();
}

class _StagePageState extends State<StagePage> {
  bool isLoading = true;
  bool isShowingCachedData = false;
  String? errorMessage;
  StageDashboard? stage;

  @override
  void initState() {
    super.initState();
    if (widget.canAccessOwnContent) {
      fetchStage();
    } else {
      isLoading = false;
    }
  }

  Future<void> fetchStage() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loaded = await infrive.getStage(widget.stageId);

      if (!mounted) return;

      setState(() {
        stage = loaded;
        isShowingCachedData = false;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (isSessionExpired(error)) {
        signOutToLogin(context);
        return;
      }

      final cached =
          error is NetworkException ? await infrive.cachedStage(widget.stageId) : null;
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          stage = cached;
          isShowingCachedData = true;
          isLoading = false;
        });
        return;
      }

      setState(() {
        errorMessage = describeError(error);
        isLoading = false;
      });
    }
  }

  void openSubStage(StageNode node) {
    if (!node.isReachable && node.children.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StagePage(
          stageId: node.id,
          stageName: node.name,
          children: node.children,
          canAccessOwnContent: node.isReachable,
        ),
      ),
    );
  }

  void openForm(FormSummary form, bool canFill) {
    if (!canFill) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to fill this form.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FormFillPage(
          formId: form.id,
          stageId: widget.stageId,
          formTitle: form.title,
        ),
      ),
    );
  }

  void openFormHistory(FormSummary form) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FormSubmissionsPage(
          formId: form.id,
          formTitle: form.title,
          stageId: widget.stageId,
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: GoogleFonts.sora(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
            letterSpacing: 1.0,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final current = stage;
    final formPerm = current?.of('Form');
    final submissionPerm = current?.of('Form Submission');
    final canViewForms = formPerm?.can('view') ?? false;
    final canViewHistory = submissionPerm?.can('view') ?? false;
    final List<FormSummary> activeForms = current != null
        ? current.forms.where((f) => f.isActive).toList()
        : const [];

    return Scaffold(
      backgroundColor: AppColors.light,
      body: Column(
        children: [
          Container(
            color: AppColors.navy,
            child: Column(
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + 8),
                AppNavBar(
                  title: 'Project Phases & Forms',
                  breadcrumb: widget.stageName.toUpperCase(),
                  trailing: widget.canAccessOwnContent
                      ? ScaleButton(
                          onTap: isLoading ? null : fetchStage,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.refresh_rounded,
                              color: AppColors.white,
                              size: 20,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
          if (isShowingCachedData) cachedDataBanner(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
                : errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: AppColors.red),
                              const SizedBox(height: 16),
                              Text(
                                errorMessage!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: fetchStage,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.navy,
                        backgroundColor: AppColors.white,
                        onRefresh: widget.canAccessOwnContent ? fetchStage : () async {},
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (!widget.canAccessOwnContent)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  "You don't have direct access to this stage — showing its sub-phases.",
                                  style: GoogleFonts.sora(fontSize: 12, color: AppColors.muted),
                                ),
                              ),
                            if (widget.canAccessOwnContent) ...[
                              if (submissionPerm != null &&
                                  submissionPerm.can('view') &&
                                  (current?.submissionCounts.isNotEmpty ?? false))
                                Container(
                                  margin: const EdgeInsets.only(bottom: 20),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: [
                                      for (final entry in current!.submissionCounts.entries)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: AppColors.light,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '${entry.key}: ${entry.value}',
                                            style: GoogleFonts.sora(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.text,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              _sectionLabel('FORMS (${activeForms.length})'),
                              if (!canViewForms)
                                Text(
                                  'You do not have access to forms on this stage.',
                                  style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
                                )
                              else if (activeForms.isEmpty)
                                Text(
                                  'No active forms on this stage.',
                                  style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
                                )
                              else
                                for (final form in activeForms)
                                  _FormCard(
                                    form: form,
                                    canFill: submissionPerm?.can('create') ?? false,
                                    canViewHistory: canViewHistory,
                                    onStart: () => openForm(
                                        form, submissionPerm?.can('create') ?? false),
                                    onHistory: () => openFormHistory(form),
                                  ),
                            ],
                            if (widget.children.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _sectionLabel('SUB-PHASES (${widget.children.length})'),
                              for (final node in widget.children)
                                StageFolderCard(node: node, onTap: () => openSubStage(node)),
                            ],
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------- EXPANDABLE FORM CARD ----------------

/// Collapsed: name + status. Expanded (tap to toggle): a history button
/// (this form's own past submissions) and a start button (fill a new one)
/// — kept apart instead of surfacing every submission inline on the stage
/// screen.
class _FormCard extends StatefulWidget {
  const _FormCard({
    required this.form,
    required this.canFill,
    required this.canViewHistory,
    required this.onStart,
    required this.onHistory,
  });

  final FormSummary form;
  final bool canFill;
  final bool canViewHistory;
  final VoidCallback onStart;
  final VoidCallback onHistory;

  @override
  State<_FormCard> createState() => _FormCardState();
}

class _FormCardState extends State<_FormCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final form = widget.form;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _formAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _formAccent.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _formAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.description_outlined, color: _formAccent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        form.title,
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        form.isActive ? 'Active' : form.status,
                        style: GoogleFonts.sora(fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.fastOutSlowIn,
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.slate,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.canViewHistory) ...[
                        ScaleButton(
                          onTap: widget.onHistory,
                          scaleBound: 0.88,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Icon(
                              Icons.history_rounded,
                              size: 16,
                              color: AppColors.slate,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      ScaleButton(
                        onTap: widget.canFill ? widget.onStart : null,
                        scaleBound: 0.88,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: widget.canFill
                                ? _formAccent
                                : AppColors.slate.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            widget.canFill ? Icons.add_rounded : Icons.lock_outline_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.fastOutSlowIn,
          ),
        ],
      ),
    );
  }
}
