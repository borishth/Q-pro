import 'package:flutter/material.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/app_errors.dart';
import '../../../core/network/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_nav_bar.dart';
import '../../../core/widgets/cached_data_banner.dart';
import '../../../core/widgets/scale_button.dart';
import '../../projects/models/project.dart';
import '../models/hierarchy.dart';
import 'stage_folder_card.dart';
import 'stage_page.dart';

// ---------------- HIERARCHY SCREEN ----------------

/// A project's top-level stages. Each stage then recurses through
/// [StagePage], which shows that stage's own forms (if reachable) *and*
/// its sub-phases on the same screen, drilling one level at a time.
class HierarchyPage extends StatefulWidget {
  final Project project;

  const HierarchyPage({super.key, required this.project});

  @override
  State<HierarchyPage> createState() => _HierarchyPageState();
}

class _HierarchyPageState extends State<HierarchyPage> {
  bool isLoading = true;
  bool isShowingCachedData = false;
  String? errorMessage;
  List<StageNode> nodes = const [];

  @override
  void initState() {
    super.initState();
    fetchHierarchy();
  }

  Future<void> fetchHierarchy() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loaded = await infrive.getHierarchy(widget.project.name);

      if (!mounted) return;

      setState(() {
        nodes = loaded.nodes;
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
          ? await infrive.cachedHierarchy(widget.project.name)
          : null;
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          nodes = cached.nodes;
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

  void openStage(StageNode node) {
    if (!node.isReachable && node.children.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StagePage(
          stageId: node.id,
          stageName: node.name,
          children: node.children,
          canAccessOwnContent: node.isReachable,
        ),
      ),
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
                  title: 'Project Phases & Forms',
                  breadcrumb: widget.project.projectName.toUpperCase(),
                  trailing: ScaleButton(
                    onTap: isLoading ? null : fetchHierarchy,
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
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
                : errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: AppColors.red),
                              const SizedBox(height: 16),
                              Text(
                                errorMessage!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: fetchHierarchy,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : nodes.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'You have no access to any stage yet.\nAsk your project admin.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            color: AppColors.navy,
                            backgroundColor: AppColors.white,
                            onRefresh: fetchHierarchy,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                                  child: Text(
                                    'SUB-PHASES (${nodes.length})',
                                    style: GoogleFonts.sora(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.muted,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                                for (final node in nodes)
                                  StageFolderCard(node: node, onTap: () => openStage(node)),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
