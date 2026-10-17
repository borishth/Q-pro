class Project {
  final String name;
  final String projectName;
  final String projectCode;
  final String status;
  final String projectManager;
  final String startDate;
  final String endDate;
  final bool isActive;

  const Project({
    required this.name,
    required this.projectName,
    required this.projectCode,
    required this.status,
    required this.projectManager,
    required this.startDate,
    required this.endDate,
    required this.isActive,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      name: json['name']?.toString() ?? '',
      projectName: json['project_name']?.toString() ?? 'Unnamed project',
      projectCode: json['project_code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Unknown',
      projectManager: json['project_manager']?.toString() ?? '',
      startDate: json['start_date']?.toString() ?? '',
      endDate: json['end_date']?.toString() ?? '',
      isActive: json['is_active'] == 1 || json['is_active'] == true,
    );
  }
}
