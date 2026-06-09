import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/auth_header.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';
import 'otp_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  int _tab = 0; // 0 = Mobile, 1 = Email
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_phone.text.trim().isEmpty) {
      setState(() => _error = 'Enter your phone number');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devOtp = await ref
          .read(authControllerProvider.notifier)
          .requestOtp(mobile: _phone.text.trim(), purpose: 'login');
      if (mounted) {
        context.push(Routes.otp, extra: OtpArgs(mobile: _phone.text.trim(), purpose: 'login', devOtp: devOtp));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginEmail() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(identifier: _email.text.trim(), password: _password.text);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const AuthHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                children: [
                  const AuthHeading(subtitle: "Choose how you'd like to continue"),
                  const SizedBox(height: 24),
                  AuthSegmentedTabs(
                    value: _tab,
                    onChanged: (i) => setState(() {
                      _tab = i;
                      _error = null;
                    }),
                    tabs: const ['Mobile no.', 'Email'],
                  ),
                  const SizedBox(height: 22),
                  if (_tab == 0)
                    PillField(controller: _phone, hint: 'Enter your Phone No.', icon: Icons.phone_outlined, keyboardType: TextInputType.phone)
                  else ...[
                    PillField(controller: _email, hint: 'Enter your Email', icon: Icons.mail_outline, keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 16),
                    PillField(controller: _password, hint: 'Enter your Password', icon: Icons.lock_outline, obscure: true),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _tab == 0 ? 'Send OTP' : 'Log in',
                    loading: _loading,
                    onPressed: _tab == 0 ? _sendOtp : _loginEmail,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? ", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                      GestureDetector(
                        onTap: () => context.go(Routes.register),
                        child: const Text('Sign Up', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
