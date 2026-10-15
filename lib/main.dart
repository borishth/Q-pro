
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const QProApp());
}

class QProApp extends StatelessWidget {
  const QProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Q-Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}

// ---------------- LOGIN SCREEN ----------------

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;
  String message = '';

  Future<void> login() async {
    final username = usernameController.text.trim();
    final password = passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        message = 'Please enter your username and password.';
      });
      return;
    }

    setState(() {
      isLoading = true;
      message = 'Logging in...';
    });

    try {
      final response = await http
          .post(
            Uri.parse(
              'http://10.0.2.2:8800/api/method/login',
            ),
            headers: {
              'Host': 'infrive.localhost',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'usr': username,
              'pwd': password,
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 &&
          data['message'] == 'Logged In') {
        final cookieHeader =
            response.headers['set-cookie'] ?? '';

        final match = RegExp(
          r'(?:^|,\s*)sid=([^;,\s]+)',
        ).firstMatch(cookieHeader);

        final sessionId = match?.group(1);

        if (sessionId == null) {
          setState(() {
            message =
                'Login succeeded, but the session cookie '
                'was not found.';
          });
          return;
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DashboardPage(
              username: username,
              sessionId: sessionId,
            ),
          ),
        );
      } else {
        setState(() {
          message = 'Login failed. Check your credentials.';
        });
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = 'Could not connect to the server.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Q-Pro'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.engineering,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 16),
              const Text(
                'Welcome to Q-Pro',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to continue',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: usernameController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Username or email',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                onSubmitted: (_) {
                  if (!isLoading) login();
                },
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: isLoading ? null : login,
                child: Text(
                  isLoading ? 'Please wait...' : 'Log In',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- DASHBOARD SCREEN ----------------

class DashboardPage extends StatelessWidget {
  final String username;
  final String sessionId;

  const DashboardPage({
    super.key,
    required this.username,
    required this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Q-Pro Dashboard'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(
            Icons.engineering,
            size: 64,
            color: Colors.blue,
          ),
          const SizedBox(height: 16),
          Text(
            'Welcome, $username!',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text('You are now inside Q-Pro.'),
          const SizedBox(height: 28),
          const Text(
            'Your Workspace',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Projects'),
              subtitle: const Text('View projects from your backend'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProjectsPage(
                      sessionId: sessionId,
                    ),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Forms'),
              subtitle: const Text('Access your forms'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Forms screen is coming next.'),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile'),
              subtitle: const Text('Manage your account'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Profile screen is coming next.'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- PROJECT DATA MODEL ----------------

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
      isActive: json['is_active'] == 1 ||
          json['is_active'] == true,
    );
  }
}

// ---------------- PROJECTS SCREEN ----------------

class ProjectsPage extends StatefulWidget {
  final String sessionId;

  const ProjectsPage({
    super.key,
    required this.sessionId,
  });

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  bool isLoading = true;
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
      final uri = Uri.parse(
        'http://10.0.2.2:8800/api/resource/Project',
      ).replace(
        queryParameters: {
          'fields': jsonEncode([
            'name',
            'project_name',
            'project_code',
            'status',
            'project_manager',
            'start_date',
            'end_date',
            'is_active',
          ]),
          'limit_page_length': '50',
        },
      );

      final response = await http
          .get(
            uri,
            headers: {
              'Host': 'infrive.localhost',
              'Accept': 'application/json',
              'Cookie': 'sid=${widget.sessionId}',
            },
          )
          .timeout(const Duration(seconds: 20));

      final decoded = jsonDecode(response.body);

      if (response.statusCode != 200) {
        final serverMessage = decoded is Map
            ? decoded['exception'] ??
                decoded['message'] ??
                'HTTP ${response.statusCode}'
            : 'HTTP ${response.statusCode}';

        throw Exception(serverMessage);
      }

      if (decoded is! Map || decoded['data'] is! List) {
        throw Exception('Unexpected response from Frappe.');
      }

      final items = decoded['data'] as List;

      final loadedProjects = items
          .map(
            (item) => Project.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        projects = loadedProjects;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = error.toString();
        isLoading = false;
      });
    }
  }

  Widget buildProjectCard(Project project) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.folder_outlined,
                  size: 32,
                  color: Colors.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.projectName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        project.projectCode.isNotEmpty
                            ? project.projectCode
                            : project.name,
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Chip(label: Text(project.status)),
              ],
            ),
            const Divider(height: 28),
            _detailRow(
              'Project manager',
              project.projectManager.isEmpty
                  ? 'Not assigned'
                  : project.projectManager,
            ),
            _detailRow(
              'Start date',
              project.startDate.isEmpty
                  ? 'Not set'
                  : project.startDate,
            ),
            _detailRow(
              'End date',
              project.endDate.isEmpty
                  ? 'Not set'
                  : project.endDate,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  project.isActive
                      ? Icons.check_circle_outline
                      : Icons.pause_circle_outline,
                  size: 18,
                  color: project.isActive
                      ? Colors.green
                      : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  project.isActive ? 'Active' : 'Inactive',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            tooltip: 'Refresh projects',
            onPressed: isLoading ? null : fetchProjects,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading projects from Frappe...'),
                ],
              ),
            )
          : errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Could not load projects',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          errorMessage!,
                          textAlign: TextAlign.center,
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
                )
              : projects.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.folder_open_outlined,
                            size: 56,
                          ),
                          const SizedBox(height: 12),
                          const Text('No projects found.'),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: fetchProjects,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: fetchProjects,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: projects.length,
                        itemBuilder: (context, index) {
                          return buildProjectCard(projects[index]);
                        },
                      ),
                    ),
    );
  }
}
