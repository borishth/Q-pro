import 'package:flutter/material.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/app_errors.dart';
import '../../../core/network/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/string_formatter.dart';
import '../../../core/widgets/cached_data_banner.dart';
import '../../../core/widgets/state_views.dart';
import '../../forms/presentation/submission_detail_page.dart';
import '../models/app_notification.dart';
import '../notification_center.dart';

// ---------------- NOTIFICATIONS SCREEN ----------------

/// What happened to the user's submissions — "sent to manager", "approved",
/// "needs rework" — as distinct from the Inbox, which is the list of things
/// still waiting on them to act.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool isLoading = true;
  bool isShowingCachedData = false;
  String? errorMessage;
  List<AppNotification> items = [];

  int get unreadCount => items.where((n) => !n.isRead).length;

  @override
  void initState() {
    super.initState();
    fetchNotifications();
  }

  Future<void> fetchNotifications() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loaded = await infrive.notifications();
      if (!mounted) return;
      setState(() {
        items = loaded;
        isShowingCachedData = false;
        isLoading = false;
      });
      // Counted server-side rather than from this page's list: the list is
      // capped at a page size, so an unread backlog past that cap would
      // otherwise under-report the badge.
      NotificationCenter.instance.refresh();
    } catch (error) {
      if (!mounted) return;
      if (isSessionExpired(error)) {
        signOutToLogin(context);
        return;
      }

      final cached =
          error is NetworkException ? await infrive.cachedNotifications() : null;
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

  /// Marks read optimistically — the row should stop looking unread the
  /// instant it's tapped, and a failed write is not worth interrupting
  /// the user over. The next refresh reconciles it either way.
  Future<void> markRead(AppNotification item) async {
    if (item.isRead) return;
    setState(() {
      items = [
        for (final n in items)
          n.name == item.name ? n.copyWith(isRead: true) : n,
      ];
    });
    NotificationCenter.instance.decrement();
    try {
      await infrive.markNotificationRead(item.name);
    } catch (_) {
      // Left as-is on screen; the next fetch restores the true state.
    }
  }

  Future<void> markAllRead() async {
    setState(() {
      items = [for (final n in items) n.copyWith(isRead: true)];
    });
    NotificationCenter.instance.clear();
    try {
      await infrive.markAllNotificationsRead();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeError(error))),
      );
      fetchNotifications();
    }
  }

  /// Swiping a card away removes it. Optimistic, like a phone's own
  /// notification shade: the row leaves immediately and only comes back if
  /// the server actually refused, so a slow connection never makes the
  /// gesture feel broken.
  Future<void> dismiss(AppNotification item, int index) async {
    setState(() => items = [...items]..removeWhere((n) => n.name == item.name));
    if (!item.isRead) NotificationCenter.instance.decrement();

    try {
      await infrive.dismissNotification(item.name);
    } catch (error) {
      if (!mounted) return;
      // Put it back exactly where it was rather than silently eating it.
      setState(() {
        final restored = [...items];
        restored.insert(index.clamp(0, restored.length), item);
        items = restored;
      });
      if (!item.isRead) {
        NotificationCenter.instance.unreadCount.value += 1;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeError(error))),
      );
    }
  }

  Future<void> open(AppNotification item) async {
    await markRead(item);
    final submission = item.submission;
    if (submission == null || submission.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubmissionDetailPage(submissionName: submission),
      ),
    );
    fetchNotifications();
  }

  /// Icon and accent per event, with a neutral fallback so a `kind` this
  /// build doesn't know about still renders sensibly.
  (IconData, Color) _appearance(String kind) => switch (kind) {
        'sent_for_approval' => (Icons.send_rounded, AppColors.navy3),
        'awaiting_action' => (Icons.assignment_late_outlined, AppColors.orange),
        'approved' => (Icons.check_circle_outline_rounded, AppColors.green),
        'rework' => (Icons.history_rounded, AppColors.yellow),
        'rejected' => (Icons.cancel_outlined, AppColors.red),
        _ => (Icons.notifications_none_rounded, AppColors.muted),
      };

  Widget buildRow(AppNotification item, int index) {
    return Dismissible(
      key: ValueKey(item.name),
      direction: DismissDirection.horizontal,
      background: _buildSwipeBackground(Alignment.centerLeft),
      secondaryBackground: _buildSwipeBackground(Alignment.centerRight),
      onDismissed: (_) => dismiss(item, index),
      child: _buildCard(item),
    );
  }

  /// What shows behind a card mid-swipe — same on both sides, so the
  /// gesture reads the same whichever way it's thrown.
  Widget _buildSwipeBackground(Alignment alignment) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      alignment: alignment,
      decoration: BoxDecoration(
        color: AppColors.tagRedBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: const Icon(Icons.delete_outline_rounded,
          color: AppColors.red, size: 22),
    );
  }

  Widget _buildCard(AppNotification item) {
    final (icon, color) = _appearance(item.kind);
    final unread = !item.isRead;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: unread ? AppColors.white : AppColors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unread ? color.withValues(alpha: 0.35) : AppColors.border,
        ),
        boxShadow: unread ? AppColors.softShadow : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => open(item),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: GoogleFonts.sora(
                                fontSize: 14,
                                fontWeight:
                                    unread ? FontWeight.w800 : FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        style: GoogleFonts.sora(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppColors.muted,
                        ),
                      ),
                      if (item.createdAt != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _timeLabel(item.createdAt!),
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Frappe sends `creation` as a server-local datetime string; fall back
  /// to showing it raw if it isn't parseable rather than dropping it.
  String _timeLabel(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return relativeTime(parsed.millisecondsSinceEpoch).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unreadCount > 0)
            IconButton(
              tooltip: 'Mark all read',
              onPressed: isLoading ? null : markAllRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: isLoading ? null : fetchNotifications,
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
                    ? _buildError()
                    : items.isEmpty
                        ? _buildEmpty()
                        : RefreshIndicator(
                            onRefresh: fetchNotifications,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              itemCount: items.length,
                              itemBuilder: (context, index) =>
                                  buildRow(items[index], index),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => const EmptyStateView(
        icon: Icons.notifications_none_rounded,
        title: 'No notifications yet',
        body: "You'll see updates here when a form you sent is approved "
            'or sent back for rework.',
      );

  Widget _buildError() => ErrorStateView(
        message: errorMessage!,
        onRetry: fetchNotifications,
      );
}
