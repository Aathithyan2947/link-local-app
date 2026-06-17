import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/auth_header.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';

class OtpArgs {
  const OtpArgs({this.mobile, this.email, this.name, required this.purpose, this.devOtp});
  final String? mobile;
  final String? email;
  final String? name;
  final String purpose; // registration | login
  final String? devOtp;
}

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.args});
  final OtpArgs args;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otp = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _devOtp;

  @override
  void initState() {
    super.initState();
    _devOtp = widget.args.devOtp;
    if (_devOtp != null) _otp.text = _devOtp!; // prefill in dev for convenience
  }

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _resend() async {
    final code = await ref.read(authControllerProvider.notifier).requestOtp(
          mobile: widget.args.mobile,
          email: widget.args.email,
          purpose: widget.args.purpose,
          name: widget.args.name,
        );
    if (mounted) {
      setState(() => _devOtp = code);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP re-sent')));
    }
  }

  Future<void> _submit() async {
    if (_otp.text.trim().length < 6) {
      setState(() => _error = 'Enter the 6-digit OTP');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).verifyOtp(
            mobile: widget.args.mobile,
            email: widget.args.email,
            otp: _otp.text.trim(),
            purpose: widget.args.purpose,
            name: widget.args.name,
          );
      // Router redirect handles navigation once authenticated.
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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                children: [
                  // Let the user go back to fix a wrong phone number / email.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _loading
                          ? null
                          : () => context.canPop() ? context.pop() : context.go(Routes.register),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: Text('Change ${widget.args.email != null ? 'email' : 'number'}'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  AuthHeading(
                    title: 'Enter OTP to Continue',
                    highlight: 'OTP',
                    subtitle: widget.args.mobile != null
                        ? 'Enter the 6-digit code sent to ${widget.args.mobile}'
                        : 'Enter 6 Digit OTP',
                  ),
                  const SizedBox(height: 28),
                  PillField(controller: _otp, hint: 'Enter OTP', icon: Icons.password, keyboardType: TextInputType.number),
                  if (_devOtp != null) ...[
                    const SizedBox(height: 8),
                    Text('Dev OTP: $_devOtp', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Didn’t receive OTP? ', style: TextStyle(color: AppColors.ink)),
                      GestureDetector(
                        onTap: _resend,
                        child: const Text('Resend',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 24),
                  PrimaryButton(label: 'Continue', loading: _loading, onPressed: _submit),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
