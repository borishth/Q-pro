import 'package:flutter/material.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

import '../../features/auth/presentation/login_page.dart';
import '../storage/outbox_db.dart';
import 'infrive_api.dart';

/// Shared SDK instance: one FrappeSDK for the app's lifetime.
late final FrappeSDK sdk;

/// Wraps every infrive_app.api.* call. Screens use this, not sdk.api directly.
late final InfriveApi infrive;

/// Sends the user back to the sign-in screen after a 401. Does not call
/// `sdk.auth.logout()` — the session is already gone server-side.
void signOutToLogin(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
    (route) => false,
  );
}

/// Shared sign-out flow for both the dashboard's "Log Out" tile and the
/// Profile screen: warns if anything is still queued in the outbox, then
/// clears the session and permission-filtered read caches before returning
/// to Login.
Future<void> performLogout(BuildContext context) async {
  final pending = await OutboxDatabase.instance.countPending();
  if (pending > 0) {
    if (!context.mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsynced changes'),
        content: Text(
          'You have $pending change${pending == 1 ? '' : 's'} waiting to '
          "sync. They'll stay queued and send next time you're online.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out anyway'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
  }

  await sdk.auth.logout();
  await OutboxDatabase.instance.clearReadCache();
  if (!context.mounted) return;
  signOutToLogin(context);
}

/// The guide's single error-handling choke point (section 9): a 401
/// signs the user out and rethrows; everything else (403, 417, network,
/// generic) is left for the caller to catch and show via
/// [describeError]/[isSessionExpired] as before. New call sites should
/// route through this; existing ones that already do the equivalent
/// check manually haven't been retrofitted, to avoid touching code
/// that's already been verified end-to-end on a device.
Future<T> guard<T>(BuildContext context, Future<T> Function() call) async {
  try {
    return await call();
  } on AuthException catch (e) {
    if (e.statusCode == 401) signOutToLogin(context);
    rethrow;
  }
}
