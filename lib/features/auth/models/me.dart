/// Response of `infrive_app.api.permissions.me`.
class Me {
  final String user;
  final String fullName;
  final bool isSuperadmin;
  final bool isProjectAdmin;

  const Me({
    required this.user,
    required this.fullName,
    required this.isSuperadmin,
    required this.isProjectAdmin,
  });

  factory Me.fromJson(Map<String, dynamic> json) {
    return Me(
      user: json['user']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      isSuperadmin: json['is_superadmin'] == true,
      isProjectAdmin: json['is_project_admin'] == true,
    );
  }
}
