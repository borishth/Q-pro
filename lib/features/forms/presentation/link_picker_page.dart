import 'package:flutter/material.dart';

import '../../../core/network/app_errors.dart';
import '../../../core/network/session.dart';
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
                          onPressed: fetchRows,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : rows.isEmpty
                  ? const Center(child: Text('No submissions found.'))
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
