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

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  int _tab = 0; // 0 = Mobile, 1 = Email
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name and phone number');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devOtp = await ref.read(authControllerProvider.notifier).requestOtp(
            mobile: _phone.text.trim(),
            purpose: 'registration',
            name: _name.text.trim(),
          );
      if (mounted) {
        context.push(Routes.otp,
            extra: OtpArgs(mobile: _phone.text.trim(), name: _name.text.trim(), purpose: 'registration', devOtp: devOtp));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _registerEmail() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name and email');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).register(
            name: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            userType: 'resident',
          );
      // Router redirect handles navigation.
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
                  if (_tab == 0) ..._mobileForm() else ..._emailForm(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _tab == 0 ? 'Send OTP' : 'Continue',
                    loading: _loading,
                    onPressed: _tab == 0 ? _sendOtp : _registerEmail,
                  ),
                  const SizedBox(height: 16),
                  _footer(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _mobileForm() => [
        PillField(controller: _name, hint: 'Full Name', icon: Icons.person_outline),
        const SizedBox(height: 16),
        PillField(controller: _phone, hint: 'Enter your Phone No.', icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
      ];

  List<Widget> _emailForm() => [
        PillField(controller: _name, hint: 'Enter your Full Name', icon: Icons.person_outline),
        const SizedBox(height: 16),
        PillField(controller: _email, hint: 'Enter your Email', icon: Icons.mail_outline, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 20),
        const Text('Create a strong password', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        PillField(controller: _password, hint: 'Create your Password', icon: Icons.lock_outline, obscure: true),
        const SizedBox(height: 16),
        PillField(controller: _confirm, hint: 'Confirm your Password', icon: Icons.lock_outline, obscure: true),
      ];

  Widget _footer(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Already have an Account? ', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        GestureDetector(
          onTap: () => context.go(Routes.login),
          child: const Text('Log in', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
