import 'package:flutter/material.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

import '../../../core/network/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../home/presentation/dashboard_page.dart';

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
      final response = await sdk.auth.login(username, password);

      if (!mounted) return;

      final fullName =
          response['full_name'] as String? ?? response['user'] as String? ?? username;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardPage(username: fullName),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        message = error is FrappeException
            ? 'Login failed.\n${error.message}'
            : 'Could not connect to the server.\n$error';
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

  InputDecoration _fieldDecoration({
    required IconData icon,
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.bodyMedium,
      prefixIcon: Icon(icon, color: AppColors.muted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.light,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.orange, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.navy, AppColors.navy2, AppColors.background],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Container(
                  width: 96,
                  height: 96,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: AppColors.glowMedium(AppColors.orange),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Q-Pro',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.displayLarge.copyWith(
                    color: AppColors.white,
                    fontSize: 32,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'UBI INFRASTRUCTURA FLORET.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.monoLabel.copyWith(letterSpacing: 2),
                ),
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.navy.withValues(alpha: 0.12),
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                      ),
                      BoxShadow(
                        color: AppColors.navy.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back', style: AppTextStyles.headingMedium),
                      const SizedBox(height: 4),
                      Text('Sign in to continue', style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 24),
                      Text('USERNAME', style: AppTextStyles.fieldLabel),
                      const SizedBox(height: 6),
                      TextField(
                        controller: usernameController,
                        autocorrect: false,
                        style: AppTextStyles.titleMedium,
                        decoration: _fieldDecoration(
                          icon: Icons.person_outline,
                          hint: 'Enter your username',
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('PASSWORD', style: AppTextStyles.fieldLabel),
                      const SizedBox(height: 6),
                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        style: AppTextStyles.titleMedium,
                        onSubmitted: (_) {
                          if (!isLoading) login();
                        },
                        decoration: _fieldDecoration(
                          icon: Icons.lock_outline,
                          hint: 'Enter your password',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password reset is coming soon.'),
                              ),
                            );
                          },
                          child: Text('Forgot Password?', style: AppTextStyles.link),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: isLoading
                              ? const []
                              : AppColors.glowMedium(AppColors.orange),
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: isLoading ? null : login,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.orange,
                              disabledBackgroundColor: AppColors.orange.withValues(alpha: 0.5),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: isLoading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
                            label: Text(
                              isLoading ? 'Please wait...' : 'Log In',
                              style: AppTextStyles.bodyLarge,
                            ),
                          ),
                        ),
                      ),
                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Center(
                        child: Text('Q-Pro Version v1.0', style: AppTextStyles.bodySmall),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
