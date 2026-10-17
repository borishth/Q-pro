import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/app_errors.dart';
import '../../../core/network/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_nav_bar.dart';
import '../../../core/widgets/scale_button.dart';
import '../models/submission_row.dart';
import 'submission_detail_page.dart';

// ---------------- FORM SUBMISSIONS (HISTORY) SCREEN ----------------

/// One form's own recent submissions on a stage — reached via the
/// history button on its [_FormCard] in [StagePage], rather than one
/// flat list mixing every form's submissions together.
class FormSubmissionsPage extends StatefulWidget {
  final String formId;
  final String formTitle;
  final String stageId;

  const FormSubmissionsPage({
    super.key,
    required this.formId,
    required this.formTitle,
    required this.stageId,
  });

  @override
  State<FormSubmissionsPage> createState() => _FormSubmissionsPageState();
}

class _FormSubmissionsPageState extends State<FormSubmissionsPage> {
  bool isLoading = true;
  String? errorMessage;
  List<SubmissionRow> rows = [];

  @override
  void initState() {
    super.initState();
    fetchRows();
  }

  Future<void> fetchRows() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loaded = await guard(
        context,
        () => infrive.getSubmissions(form: widget.formId, stage: widget.stageId, limit: 50),
      );
      if (!mounted) return;
      setState(() {
        rows = loaded;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (isSessionExpired(error)) return;
      setState(() {
        errorMessage = describeError(error);
        isLoading = false;
      });
    }
  }

  void openSubmission(SubmissionRow row) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => SubmissionDetailPage(submissionName: row.name),
          ),
        )
        .then((_) => fetchRows());
  }

  Widget buildRow(SubmissionRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openSubmission(row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.description_outlined, color: AppColors.navy, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.status,
                      style: GoogleFonts.sora(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (row.submittedBy != null) row.submittedBy!,
                        if (row.modified != null) row.modified!,
                      ].join(' · '),
                      style: GoogleFonts.sora(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.slate, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  title: widget.formTitle,
                  breadcrumb: 'SUBMISSION HISTORY',
                  trailing: ScaleButton(
                    onTap: isLoading ? null : fetchRows,
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
                  ),
                ),
              ],
            ),
          ),
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
                                onPressed: fetchRows,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : rows.isEmpty
                        ? Center(
                            child: Text(
                              'No submissions yet for this form.',
                              style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
                            ),
                          )
                        : RefreshIndicator(
                            color: AppColors.navy,
                            backgroundColor: AppColors.white,
                            onRefresh: fetchRows,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              children: [for (final row in rows) buildRow(row)],
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
