import 'package:flutter/material.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

import '../../../core/network/app_errors.dart';
import '../../../core/network/session.dart';
import '../../../core/widgets/cached_data_banner.dart';
import '../../forms/presentation/submission_detail_page.dart';
import '../models/inbox_row.dart';

// ---------------- INBOX SCREEN ----------------

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  bool isLoading = true;
  bool isShowingCachedData = false;
  String? errorMessage;
  List<InboxRow> items = [];

  @override
  void initState() {
    super.initState();
    fetchInbox();
  }

  Future<void> fetchInbox() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loaded = await infrive.inbox();

      if (!mounted) return;

      setState(() {
        items = loaded;
        isShowingCachedData = false;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (isSessionExpired(error)) {
        signOutToLogin(context);
        return;
      }

      final cached = error is NetworkException ? await infrive.cachedInbox() : null;
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          items = cached;
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

  Future<void> openSubmission(InboxRow row) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubmissionDetailPage(submissionName: row.name),
      ),
    );
    fetchInbox();
  }

  Widget buildRow(InboxRow row) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.assignment_outlined),
        title: Text(row.form),
        subtitle: Text('${row.stage} · ${row.status}'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => openSubmission(row),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: isLoading ? null : fetchInbox,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (isShowingCachedData) cachedDataBanner(),
          Expanded(
            child: isLoading
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
                                onPressed: fetchInbox,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : items.isEmpty
                        ? const Center(child: Text('Nothing waiting on you.'))
                        : RefreshIndicator(
                            onRefresh: fetchInbox,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: items.length,
                              itemBuilder: (context, index) => buildRow(items[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
