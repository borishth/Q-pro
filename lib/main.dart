import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

import 'core/network/infrive_api.dart';
import 'core/network/session.dart';
import 'core/services/connectivity_service.dart';
import 'core/storage/outbox_sync.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/home/presentation/dashboard_page.dart';

/// Override at launch with `--dart-define=API_BASE_URL=...` — e.g.
/// `http://10.0.2.2:8800/` for the Android emulator, which can't reach the
/// dev machine's LAN IP the way a real phone on the same WiFi can.
const _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://172.16.117.47:8800/',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sdk = FrappeSDK(baseUrl: _baseUrl);
  await sdk.initialize(true); // tries to restore a stored session
  infrive = InfriveApi(sdk.api);
  await initConnectivity();
  OutboxSync.init(infrive);
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
///
/// Animated rather than popped in and out — the banner displaces the whole
/// app below it, so appearing instantly reads as a layout glitch.
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
            return AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: online && pending == 0
                  ? const SizedBox(width: double.infinity)
                  : _BannerBody(online: online, pending: pending),
            );
          },
        );
      },
    );
  }
}

class _BannerBody extends StatelessWidget {
  const _BannerBody({required this.online, required this.pending});

  final bool online;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final changeWord = 'change${pending == 1 ? '' : 's'}';
    final (title, detail) = online
        ? ('Syncing', '$pending $changeWord to go')
        : (
            'Offline',
            pending > 0
                ? "$pending $changeWord will sync when you're back online"
                : "Changes will sync when you're back online",
          );

    // Syncing is transient and reads as progress, so it takes the navy
    // surface; offline is a state the user needs to keep in mind, so it
    // takes the attention colour.
    final tint = online ? AppColors.navy3 : AppColors.orange2;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: online
              ? const [AppColors.navy2, AppColors.navy3]
              : const [AppColors.orange2, AppColors.orange],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: AppColors.glowSubtle(tint),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm + 2,
            AppSpacing.lg,
            AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              _Glyph(online: online),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.sora(
                        color: AppColors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      detail,
                      style: GoogleFonts.sora(
                        color: AppColors.white.withValues(alpha: 0.82),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (pending > 0) _PendingPill(count: pending),
            ],
          ),
        ),
      ),
    );
  }
}

/// A spinner while draining, a cloud once there's nothing to send.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: 28,
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: online
          ? const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppColors.white),
              ),
            )
          : const Icon(
              Icons.cloud_off_rounded,
              size: 16,
              color: AppColors.white,
            ),
    );
  }
}

/// The queue depth, so the number stays readable at a glance instead of
/// being buried in the sentence.
class _PendingPill extends StatelessWidget {
  const _PendingPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: GoogleFonts.sora(
          color: AppColors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
