import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/session.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/storage/outbox_sync.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/scale_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/models/me.dart';
import '../../drafts/presentation/drafts_page.dart';

// ---------------- PROFILE SCREEN ----------------

class ProfilePage extends StatefulWidget {
  final Me? me;
  final String username;

  const ProfilePage({super.key, required this.me, required this.username});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    // The sync card reads the live outbox count; make sure it's current
    // rather than whatever the last drain pass happened to leave behind.
    OutboxSync.instance.refreshPendingCount();
  }

  Me? get me => widget.me;

  String get _displayName =>
      me?.fullName.isNotEmpty == true ? me!.fullName : widget.username;

  (String, IconData) get _role => switch (me) {
        Me(isSuperadmin: true) => ('Superadmin', Icons.shield_outlined),
        Me(isProjectAdmin: true) =>
          ('Project admin', Icons.admin_panel_settings_outlined),
        Me() => ('Member', Icons.person_outline_rounded),
        null => ('Signed in', Icons.person_outline_rounded),
      };

  String get _initials => _displayName
      .split(' ')
      .where((e) => e.isNotEmpty)
      .map((e) => e[0])
      .take(2)
      .join()
      .toUpperCase();

  @override
  Widget build(BuildContext context) {
    final (roleLabel, roleIcon) = _role;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHero(roleLabel, roleIcon),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxl,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('ACCOUNT'),
                const SizedBox(height: AppSpacing.md),
                _Card(
                  children: [
                    _InfoRow(
                      icon: Icons.badge_outlined,
                      label: 'User ID',
                      value: me?.user.isNotEmpty == true
                          ? me!.user
                          : widget.username,
                      mono: true,
                    ),
                    const _RowDivider(),
                    _InfoRow(
                      icon: roleIcon,
                      label: 'Role',
                      value: roleLabel,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                const _SectionLabel('SYNC'),
                const SizedBox(height: AppSpacing.md),
                _buildSyncCard(),
                const SizedBox(height: AppSpacing.xxxl),
                OutlinedButton.icon(
                  onPressed: () => performLogout(context),
                  icon: const Icon(Icons.logout_rounded,
                      size: 18, color: AppColors.red),
                  label: Text(
                    'Log out',
                    style: GoogleFonts.sora(
                      color: AppColors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.red.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                    backgroundColor: AppColors.tagRedBg,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Center(
                  child: Text(
                    'Q-PRO',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted.withValues(alpha: 0.6),
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Navy header the avatar sits *inside* rather than floating on an empty
  /// page — it anchors the identity block instead of leaving it adrift in
  /// white space. The gradient starts on the same navy as the themed app
  /// bar, so the two read as one panel with no seam between them.
  Widget _buildHero(String roleLabel, IconData roleIcon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.navy, AppColors.navy3],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
            child: UserAvatar(radius: 38, initials: _initials),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            _displayName,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.white,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(roleIcon, size: 14, color: Colors.white),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  roleLabel.toUpperCase(),
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Live outbox state, straight from the same notifiers the Drafts screen
  /// and the offline banner read — and a way through to the drafts.
  Widget _buildSyncCard() {
    return ValueListenableBuilder<bool>(
      valueListenable: isOnline,
      builder: (context, online, _) {
        return ValueListenableBuilder<int>(
          valueListenable: OutboxSync.instance.pendingCount,
          builder: (context, pending, _) {
            final clear = pending == 0;
            final color = clear
                ? AppColors.green
                : (online ? AppColors.yellow : AppColors.muted);
            final title = clear
                ? 'Everything is synced'
                : '$pending change${pending == 1 ? '' : 's'} waiting to sync';
            final subtitle = clear
                ? (online ? 'Connected' : 'Offline — nothing pending')
                : (online ? 'Syncing now' : "Will send when you're back online");

            return ScaleButton(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DraftsPage()),
              ),
              child: _Card(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            clear
                                ? Icons.check_circle_outline_rounded
                                : (online
                                    ? Icons.sync_rounded
                                    : Icons.cloud_off_rounded),
                            size: 20,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.sora(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: GoogleFonts.sora(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.muted),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Small all-caps heading above each group of cards.
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Text(
        text,
        style: GoogleFonts.ibmPlexMono(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.muted,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

/// White rounded panel matching the app's card theme, with the soft
/// elevation the dashboard's surfaces use.
class _Card extends StatelessWidget {
  final List<Widget> children;

  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(children: children),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => const Divider(
        height: 1,
        thickness: 1,
        indent: AppSpacing.lg + 40 + AppSpacing.md,
        endIndent: AppSpacing.lg,
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool mono;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.light,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: AppColors.navy3),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: mono
                      ? GoogleFonts.ibmPlexMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        )
                      : GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
