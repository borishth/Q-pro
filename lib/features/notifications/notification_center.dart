import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/session.dart';
import '../../core/services/connectivity_service.dart';

/// Holds the unread notification count so the dashboard's bell badge and
/// the notifications screen stay in step without either owning the other.
/// Same shape as `OutboxSync.pendingCount` — a notifier screens listen to
/// rather than each re-fetching on their own schedule.
class NotificationCenter {
  NotificationCenter._();
  static final NotificationCenter instance = NotificationCenter._();

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// True once a refresh has actually reached the server. Until then the
  /// badge stays hidden rather than claiming a confident zero.
  final ValueNotifier<bool> isAvailable = ValueNotifier<bool>(false);

  Timer? _poll;

  /// How often the badge re-checks while a screen is watching it. The call
  /// is a single COUNT, so this is cheap; the point is that a notification
  /// arriving while the user sits on the dashboard shows up on its own
  /// rather than waiting for them to open the bell and come back.
  static const pollInterval = Duration(seconds: 30);

  /// Refreshes now, then keeps refreshing until [stopPolling]. Safe to call
  /// again — it replaces any timer already running rather than stacking a
  /// second one.
  void startPolling() {
    _poll?.cancel();
    refresh();
    _poll = Timer.periodic(pollInterval, (_) {
      // Offline the call can only fail, and failing would flip the badge
      // to unavailable for no reason. Wait for the connection instead.
      if (isOnline.value) refresh();
    });
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// Pulls the current count. Never throws: the badge is decoration, and a
  /// dashboard must not fail to build because the count couldn't load.
  /// A failure just leaves the last known value and marks it unavailable.
  Future<void> refresh() async {
    try {
      unreadCount.value = await infrive.unreadNotificationCount();
      isAvailable.value = true;
    } catch (_) {
      isAvailable.value = false;
    }
  }

  /// Applied locally after marking something read, so the badge reacts
  /// immediately instead of waiting for the next round trip.
  void decrement([int by = 1]) {
    unreadCount.value = (unreadCount.value - by).clamp(0, 1 << 31);
  }

  void clear() {
    unreadCount.value = 0;
  }
}
