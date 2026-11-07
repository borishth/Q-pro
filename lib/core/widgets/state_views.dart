import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// The placeholder a screen shows instead of its content: a failed load, or
/// a load that succeeded and found nothing.
///
/// Every screen used to hand-roll these, which drifted — some reached for
/// `Colors.red`, some for [AppColors.red], none for the card surface the
/// rest of the app is built from. One widget keeps them identical.

/// Shown when a fetch failed.
///
/// Being offline is not treated as an error. It is an expected, recoverable
/// state on a site with no signal, so it gets the calm navy treatment and
/// plain language rather than a red alarm — the red is kept for a genuine
/// server or data problem, which is the thing actually worth noticing. The
/// presentation follows [isOnline] live, so walking back into signal
/// re-colours the card without the screen having to rebuild it.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  /// The failure as [describeError] rendered it. Shown only when online —
  /// offline, the SDK's own wording ("No internet connection") says less
  /// than the offline copy below, and reads like something broke.
  final String message;

  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isOnline,
      builder: (context, online, _) => _StatePanel(
        icon: online ? Icons.error_outline_rounded : Icons.cloud_off_rounded,
        tint: online ? AppColors.red : AppColors.navy3,
        title: online ? "That didn't load" : "You're offline",
        body: online
            ? message
            : "This screen hasn't been saved to this device yet, so there's "
                'nothing to show until you have a connection.',
        actionLabel: onRetry == null ? null : retryLabel,
        actionIcon: Icons.refresh_rounded,
        onAction: onRetry,
      ),
    );
  }
}

/// Shown when a fetch succeeded and there was simply nothing to list.
/// Distinct from [ErrorStateView] on purpose: nothing has gone wrong, so
/// it stays neutral and offers no retry unless the caller wants one.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    this.body,
    this.icon = Icons.inbox_outlined,
    this.onRetry,
    this.retryLabel = 'Refresh',
  });

  final String title;
  final String? body;
  final IconData icon;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: icon,
      tint: AppColors.slate,
      title: title,
      body: body,
      actionLabel: onRetry == null ? null : retryLabel,
      actionIcon: Icons.refresh_rounded,
      onAction: onRetry,
    );
  }
}

/// The shared card both states render into: a tinted icon chip, a Sora
/// title, optional muted body, optional action. Scrollable so it still
/// centres on a short screen and never overflows on a long message.
class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.tint,
    required this.title,
    this.body,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String? body;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: AppSpacing.xxxl,
          ),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 26, color: tint),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.headingMedium,
              ),
              if (body != null && body!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption,
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon, size: 18),
                    label: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
