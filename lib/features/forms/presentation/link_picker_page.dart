import 'package:flutter/material.dart';

import '../../../core/network/app_errors.dart';
import '../../../core/network/session.dart';
import '../../../core/widgets/state_views.dart';
import '../models/submission_row.dart';

// ---------------- LINK FIELD PICKER ----------------

class LinkPickerPage extends StatefulWidget {
  final String formId;
  final String? project;

  const LinkPickerPage({super.key, required this.formId, this.project});

  @override
  State<LinkPickerPage> createState() => _LinkPickerPageState();
}

class _LinkPickerPageState extends State<LinkPickerPage> {
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
        () => infrive.getSubmissions(
          project: widget.project,
          form: widget.formId,
          limit: 50,
        ),
      );

      if (!mounted) return;
      setState(() {
        rows = loaded;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (isSessionExpired(error)) {
        return;
      }

      setState(() {
        errorMessage = describeError(error);
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select submission'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: isLoading ? null : fetchRows,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? ErrorStateView(
                  message: errorMessage!,
                  onRetry: fetchRows,
                )
              : rows.isEmpty
                  ? const EmptyStateView(
                      icon: Icons.link_off_rounded,
                      title: 'Nothing to link to',
                      body: 'This form has no submissions yet, so there is '
                          'nothing to pick.',
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(row.name),
                          subtitle: Text(row.status),
                          onTap: () => Navigator.of(context).pop(row.name),
                        );
                      },
                    ),
    );
  }
}
