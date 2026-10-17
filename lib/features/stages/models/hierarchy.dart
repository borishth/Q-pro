import '../../../core/models/permissions.dart';

/// One node of a project's stage tree, from `hierarchy.get_hierarchy`.
class StageNode {
  const StageNode({
    required this.id,
    required this.name,
    required this.code,
    required this.type,
    required this.contextOnly,
    required this.permissions,
    required this.children,
  });

  final String id;
  final String name;
  final String code;
  final String type;
  final bool contextOnly;
  final Permissions permissions;
  final List<StageNode> children;

  /// An ancestor shown only to give context to a reachable descendant is
  /// `contextOnly` with every permission false; it is not tappable.
  bool get isReachable => !contextOnly && permissions.can('view');

  factory StageNode.fromJson(Map<String, dynamic> json) => StageNode(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        contextOnly: json['context_only'] == true,
        permissions: Permissions.fromJson(
          json['permissions'] as Map<String, dynamic>?,
        ),
        children: [
          for (final c in (json['children'] as List? ?? const []))
            StageNode.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
      );
}

/// The project header returned alongside the stage tree.
class HierarchyProjectInfo {
  const HierarchyProjectInfo({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
  });

  final String id;
  final String name;
  final String code;
  final String status;

  factory HierarchyProjectInfo.fromJson(Map<String, dynamic> json) =>
      HierarchyProjectInfo(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
      );
}

/// Response of `hierarchy.get_hierarchy`: the stage tree the current user
/// can see, scoped to one project.
class Hierarchy {
  const Hierarchy({required this.project, required this.nodes});

  final HierarchyProjectInfo project;
  final List<StageNode> nodes;

  factory Hierarchy.fromJson(Map<String, dynamic> json) => Hierarchy(
        project: HierarchyProjectInfo.fromJson(
          Map<String, dynamic>.from(json['project'] as Map? ?? const {}),
        ),
        nodes: [
          for (final n in (json['nodes'] as List? ?? const []))
            StageNode.fromJson(Map<String, dynamic>.from(n as Map)),
        ],
      );
}
