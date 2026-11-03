import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/network/session.dart';
import '../../../core/storage/outbox_sync.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/floating_bottom_nav_bar.dart';
import '../../../core/widgets/scale_button.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/models/me.dart';
import '../../drafts/presentation/drafts_page.dart';
import '../../inbox/presentation/inbox_page.dart';
import '../../notifications/notification_center.dart';
import '../../notifications/presentation/notifications_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../projects/presentation/projects_page.dart';

// ---------------- DASHBOARD SCREEN ----------------

class DashboardPage extends StatefulWidget {
  final String username;

  const DashboardPage({
    super.key,
    required this.username,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  Me? me;

  late Timer _timer;
  final ScrollController _scrollController = ScrollController();
  DateTime _now = DateTime.now();
  bool _showStickyHeader = false;

  @override
  void initState() {
    super.initState();
    loadMe();
    WidgetsBinding.instance.addObserver(this);
    NotificationCenter.instance.startPolling();
    _scrollController.addListener(_onScroll);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationCenter.instance.stopPolling();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _timer.cancel();
    super.dispose();
  }

  /// A backgrounded app's timers don't fire, so the badge would be stale
  /// the moment the user comes back. Re-check on resume, and don't keep a
  /// timer alive while nobody can see the result.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationCenter.instance.startPolling();
    } else if (state == AppLifecycleState.paused) {
      NotificationCenter.instance.stopPolling();
    }
  }

  void _onScroll() {
    final show = _scrollController.offset > 140;
    if (show != _showStickyHeader) {
      setState(() => _showStickyHeader = show);
    }
  }

  Future<void> loadMe() async {
    try {
      final loaded = await infrive.me();
      if (!mounted) return;
      setState(() {
        me = loaded;
      });
    } catch (_) {
      // Keep showing the cached username from login; the Projects screen
      // will surface any real auth problem.
    }
  }

  Future<void> openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsPage()),
    );
    NotificationCenter.instance.refresh();
  }

  /// Anything that can change the count — approving from the Inbox,
  /// submitting a form — lands back here, so re-check on return instead of
  /// waiting out the poll interval.
  Future<void> _pushAndRefresh(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
    NotificationCenter.instance.refresh();
  }

  void openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfilePage(me: me, username: widget.username)),
    );
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$feature screen is coming next.',
          style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String get _displayName => me?.fullName.isNotEmpty == true ? me!.fullName : widget.username;

  String get _formattedTime => DateFormat('h:mm a').format(_now);
  String get _formattedDate => DateFormat('EEE, MMM d').format(_now).toUpperCase();
  String get _formattedFullDate => DateFormat('EEEE, d MMMM yyyy').format(_now);

  void _handleNavTap(int index) {
    switch (index) {
      case 0:
        _comingSoon('Analytics');
        break;
      case 1:
        _comingSoon('Calendar');
        break;
      case 2:
        // Already home.
        break;
      case 3:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DraftsPage()),
        );
        break;
      case 4:
        openProfile();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: loadMe,
            color: AppColors.navy,
            backgroundColor: AppColors.white,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroHeader(context),
                  _buildQuickActionGrid(context),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
          _buildStickyMiniHeader(context),
        ],
      ),
      bottomNavigationBar: FloatingBottomNavBar(
        currentIndex: 2,
        onTap: _handleNavTap,
        badges: {3: OutboxSync.instance.pendingCount},
      ),
    );
  }

  Widget _buildStickyMiniHeader(BuildContext context) {
    final hour = _now.hour;
    final String greeting;
    if (hour < 12) {
      greeting = 'GOOD MORNING,';
    } else if (hour < 17) {
      greeting = 'GOOD AFTERNOON,';
    } else {
      greeting = 'GOOD EVENING,';
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.fastOutSlowIn,
      top: _showStickyHeader ? 0 : -140,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: _showStickyHeader ? 1.0 : 0.0,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset('assets/images/background.jpeg', fit: BoxFit.cover),
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      MediaQuery.of(context).padding.top + 10,
                      24,
                      16,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            greeting,
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFD97706),
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _displayName,
                            style: GoogleFonts.sora(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context) {
    final initials = _displayName
        .split(' ')
        .where((e) => e.isNotEmpty)
        .map((e) => e[0])
        .take(2)
        .join()
        .toUpperCase();

    final screenHeight = MediaQuery.of(context).size.height;
    final paddingTop = MediaQuery.of(context).padding.top;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/background.jpeg', fit: BoxFit.cover),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Container(
              constraints: BoxConstraints(minHeight: screenHeight + 60),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, paddingTop + 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ScaleButton(
                          onTap: openProfile,
                          child: UserAvatar(radius: 20, initials: initials),
                        ),
                        ScaleButton(
                          onTap: openNotifications,
                          child: _buildNotificationBell(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'WELCOME BACK,',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _displayName,
                      style: GoogleFonts.sora(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formattedTime,
                            style: GoogleFonts.sora(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(width: 1, height: 12, color: const Color(0xFFCBD5E1)),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 12,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formattedDate,
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          const Text('🌤️', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              child: _MarqueeText(
                                text:
                                    'TODAY: 28°C • SUNNY & CLEAR • GUWAHATI, INDIA • $_formattedFullDate • $_formattedTime',
                                style: GoogleFonts.ibmPlexMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF334155),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildPlatformOverviewCard(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformOverviewCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: const Color(0xFFFF6B00).withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFFEDD5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6B00),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ENTERPRISE QC PLATFORM',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFC2410C),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF64748B)),
                ],
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Q-Pro',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                    ),
                    const TextSpan(text: ' is an '),
                    TextSpan(
                      text: 'enterprise quality management & inspection platform',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                    ),
                    const TextSpan(
                      text: ' designed to digitize field inspections and quality assurance workflows. It enables inspectors, engineers, and project managers to complete ',
                    ),
                    TextSpan(
                      text: 'structured inspection checklists',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                    ),
                    const TextSpan(text: ', capture '),
                    TextSpan(
                      text: 'photographic evidence',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                    ),
                    const TextSpan(text: ', and monitor project quality in '),
                    TextSpan(
                      text: 'real time',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: const Color(0xFF0284C7)),
                    ),
                    const TextSpan(text: '. By replacing paper-based inspections with a '),
                    TextSpan(
                      text: 'centralized digital system',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                    ),
                    const TextSpan(
                      text: ', Q-pro improves accuracy, traceability, collaboration, and reporting across construction projects.',
                    ),
                  ],
                ),
                style: GoogleFonts.sora(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E293B),
                  height: 1.6,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildOverviewTag(Icons.fact_check_outlined, 'Digital Checklists'),
                  _buildOverviewTag(Icons.camera_alt_outlined, 'Photo Evidence'),
                  _buildOverviewTag(Icons.analytics_outlined, 'Real-time QA'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF0284C7)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.sora(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  /// Bell in the header: *what happened* to the user's submissions.
  /// Deliberately distinct from the Inbox tile below, which is *what still
  /// needs them* — before this the two were the same screen behind two
  /// different entry points.
  Widget _buildNotificationBell() {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationCenter.instance.unreadCount,
      builder: (context, unread, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
              ),
              child: Icon(
                unread > 0
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: 20,
                color: const Color(0xFF0F172A),
              ),
            ),
            if (unread > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  constraints: const BoxConstraints(minWidth: 18),
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.sora(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Mirrors the real destinations this app has today (Projects, Inbox,
  // Drafts, Profile) plus a still-placeholder module (Forms).
  // Log Out lives on the Profile screen now, not as its own tile here.
  Widget _buildQuickActionGrid(BuildContext context) {
    final actions = [
      _QuickActionData(
        title: 'My Dashboard',
        subtitle: 'View projects from ',
        icon: Icons.folder_outlined,
        color: const Color(0xFF2563EB),
        gradient: AppColors.gradientBlue,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProjectsPage()),
        ),
      ),
      _QuickActionData(
        title: 'Inbox',
        subtitle: 'Submissions waiting on you',
        icon: Icons.inbox_outlined,
        color: const Color(0xFF0284C7),
        gradient: AppColors.gradientBlue,
        onTap: () => _pushAndRefresh(const InboxPage()),
      ),
      _QuickActionData(
        title: 'Forms',
        subtitle: 'Access your forms',
        icon: Icons.description_outlined,
        color: const Color(0xFF7C3AED),
        gradient: AppColors.gradientPurple,
        onTap: () => _comingSoon('Forms'),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Workspace',
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.18,
            ),
            itemBuilder: (context, index) {
              final action = actions[index];
              return ScaleButton(
                onTap: action.onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                      ...AppColors.glowSubtle(action.color),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: action.gradient,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: AppColors.glowMedium(action.color),
                        ),
                        child: Icon(action.icon, color: Colors.white, size: 24),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        action.title,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        action.subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.sora(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  late final ScrollController _scrollController;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
  }

  Future<void> _startMarquee() async {
    while (!_isDisposed && mounted) {
      if (!_scrollController.hasClients) {
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) {
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }

      final durationSeconds = (maxScroll / 25).clamp(5.0, 25.0).toInt();
      await _scrollController.animateTo(
        maxScroll,
        duration: Duration(seconds: durationSeconds),
        curve: Curves.linear,
      );

      if (!_isDisposed && mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fullText = '${widget.text}   •   ${widget.text}   •   ${widget.text}';
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(fullText, style: widget.style),
    );
  }
}

class _QuickActionData {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _QuickActionData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.gradient,
    required this.onTap,
  });
}
