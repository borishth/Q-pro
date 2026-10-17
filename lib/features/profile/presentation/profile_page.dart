import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/models/me.dart';

// ---------------- PROFILE SCREEN ----------------

class ProfilePage extends StatelessWidget {
  final Me? me;
  final String username;

  const ProfilePage({super.key, required this.me, required this.username});

  String get _displayName => me?.fullName.isNotEmpty == true ? me!.fullName : username;

  String get _role => switch (me) {
        Me(isSuperadmin: true) => 'Superadmin',
        Me(isProjectAdmin: true) => 'Project admin',
        Me() => 'Member',
        null => 'Signed in',
      };

  @override
  Widget build(BuildContext context) {
    final initials = _displayName
        .split(' ')
        .where((e) => e.isNotEmpty)
        .map((e) => e[0])
        .take(2)
        .join()
        .toUpperCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 12),
          Center(child: UserAvatar(radius: 40, initials: initials)),
          const SizedBox(height: 16),
          Text(
            _displayName,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            _role,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
          ),
          if (me != null && me!.user.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              me!.user,
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexMono(fontSize: 12, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () => performLogout(context),
            icon: const Icon(Icons.logout_rounded, color: AppColors.red),
            label: Text('Log out', style: GoogleFonts.sora(color: AppColors.red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
