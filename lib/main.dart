import 'package:flutter/material.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

import 'core/network/infrive_api.dart';
import 'core/network/session.dart';
import 'core/services/connectivity_service.dart';
import 'core/storage/outbox_sync.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/home/presentation/dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sdk = FrappeSDK(baseUrl: 'http://10.0.2.2:8800/');
  await sdk.initialize(true); // tries to restore a stored session
  infrive = InfriveApi(sdk.api);
  await initConnectivity();
  OutboxSync.init(infrive, sdk.api);
  OutboxSync.instance.start();
  runApp(QProApp(startLoggedIn: sdk.isAuthenticated));
}

class QProApp extends StatelessWidget {
  final bool startLoggedIn;

  const QProApp({super.key, required this.startLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Q-Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) => Column(
        children: [
          _ConnectivityBanner(),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
      home: startLoggedIn
          ? DashboardPage(
              username: sdk.auth.currentUserInfo?.fullName ??
                  sdk.auth.currentUserInfo?.email ??
                  'User',
            )
          : const LoginPage(),
    );
  }
}

/// Shown above every screen: offline (with the outbox depth once there's
/// something queued) or, once back online, a brief "syncing" note while
/// the outbox drains. Hidden once online with nothing pending.
class _ConnectivityBanner extends StatelessWidget {
  const _ConnectivityBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isOnline,
      builder: (context, online, _) {
        return ValueListenableBuilder<int>(
          valueListenable: OutboxSync.instance.pendingCount,
          builder: (context, pending, _) {
            if (online && pending == 0) return const SizedBox.shrink();

            final changeWord = 'change${pending == 1 ? '' : 's'}';
            final text = !online
                ? (pending > 0
                    ? "Offline — $pending $changeWord will sync when you're back online."
                    : "Offline — changes will sync when you're back online.")
                : 'Syncing $pending $changeWord…';

            return Material(
              color: online ? Colors.blue.shade700 : Colors.orange.shade800,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
