import 'package:flutter/material.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/app_errors.dart';
import '../../../core/network/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_nav_bar.dart';
import '../../../core/widgets/cached_data_banner.dart';
import '../../../core/widgets/scale_button.dart';
import '../../../core/widgets/status_tag.dart';
import '../../stages/presentation/hierarchy_page.dart';
import '../models/project.dart';

// ---------------- PROJECTS SCREEN ----------------

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  bool isLoading = true;
  bool isShowingCachedData = false;
  String? errorMessage;
  List<Project> projects = [];

  @override
  void initState() {
    super.initState();
    fetchProjects();
  }

  Future<void> fetchProjects() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loadedProjects = await infrive.listProjects();

      if (!mounted) return;

      setState(() {
        projects = loadedProjects;
        isShowingCachedData = false;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (isSessionExpired(error)) {
        signOutToLogin(context);
        return;
      }

      final cached = error is NetworkException
          ? await infrive.cachedProjects()
          : null;
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          projects = cached;
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

  void openProject(Project project) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HierarchyPage(project: project)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.light,
      body: Column(
        children: [
          Container(
            color: AppColors.navy,
            child: Column(
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + 8),
                AppNavBar(
                  title: 'Projects',
                  breadcrumb: 'Q-PRO · ${projects.length} PROJECTS',
                  trailing: ScaleButton(
                    onTap: isLoading ? null : fetchProjects,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: AppColors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isShowingCachedData) cachedDataBanner(),
          Expanded(child: _buildProjectsBody()),
        ],
      ),
    );
  }

  Widget _buildProjectsBody() {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.navy),
            const SizedBox(height: 16),
            Text(
              'Loading projects from Frappe...',
              style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.red),
              const SizedBox(height: 16),
              Text(
                'Could not load projects',
                style: GoogleFonts.sora(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: fetchProjects,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_outlined, size: 56, color: AppColors.slate),
            const SizedBox(height: 12),
            Text(
              'No projects found.',
              style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: fetchProjects,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.navy,
      backgroundColor: AppColors.white,
      onRefresh: fetchProjects,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: projects.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) => _ProjectCard(
          project: projects[index],
          index: index,
          onTap: () => openProject(projects[index]),
        ),
      ),
    );
  }
}

// ---------------- PROJECT CARD ----------------

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.index,
    required this.onTap,
  });

  final Project project;
  final int index;
  final VoidCallback onTap;

  // Cycled by card index so adjacent cards read as visually distinct,
  // purely decorative — there's no real geo data behind this thumbnail.
  static const _gradients = [
    (0xFFD4E3F7, 0xFFB8CCEE),
    (0xFFD4E8D4, 0xFFB8D4B8),
    (0xFFF7D4D4, 0xFFEEB8B8),
    (0xFFFEF3E8, 0xFFEED8B8),
  ];

  @override
  Widget build(BuildContext context) {
    final gradient = _gradients[index % _gradients.length];
    final pathLine =
        project.projectCode.isNotEmpty ? project.projectCode : project.name;

    final footerParts = [
      if (project.projectManager.isNotEmpty) project.projectManager,
      if (project.startDate.isNotEmpty) project.startDate,
      if (project.endDate.isNotEmpty) '→ ${project.endDate}',
    ];
    final footerText = footerParts.isEmpty ? project.status : footerParts.join(' · ');

    return ScaleButton(
      onTap: onTap,
      scaleBound: 0.98,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    project.projectName,
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusTag(
                  label: project.status.toUpperCase(),
                  type: project.isActive ? TagType.green : TagType.red,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: AppColors.slate, size: 13),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    pathLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sora(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ProjectMapThumbnail(startColor: gradient.$1, endColor: gradient.$2),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    footerText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.ibmPlexMono(fontSize: 11, color: AppColors.muted),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppColors.light,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_right, size: 14, color: AppColors.navy),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectMapThumbnail extends StatelessWidget {
  const _ProjectMapThumbnail({required this.startColor, required this.endColor});

  final int startColor;
  final int endColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(startColor), Color(endColor)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              painter: _GridPainter(),
              size: Size.infinite,
            ),
          ),
          const Center(
            child: _MapPin(),
          ),
        ],
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        color: AppColors.orange,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.location_on, color: Colors.white, size: 12),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x336482B4)
      ..strokeWidth = 1;
    const step = 20.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
