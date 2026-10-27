import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validation/password_rules.dart';
import '../../../core/widgets/auth_header.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/auth_repository.dart';

/// Forgot password (BUG-066): a code to the account's email or mobile number, then a new
/// password with it. Pops with the identifier once the password is set, so Login can fill it
/// in. Mobile sign-in has no password (it's a one-time code each time), so it's reached from
/// the Email tab and from Change Password.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.identifier});

  /// Pre-filled email or mobile number.
  final String? identifier;

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final _identifier = TextEditingController(text: widget.identifier?.trim() ?? '');
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  static final _emailRe = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
  static final _mobileRe = RegExp(r'^[0-9]{10}$');

  bool _codeSent = false;
  bool _loading = false;
  String? _devOtp;
  String? _error;
  String? _identifierError;
  String? _codeError;
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _id => _identifier.text.trim();

  Future<void> _sendCode() async {
    final id = _id;
    final problem = id.isEmpty
        ? 'Enter your email or mobile number'
        : (_emailRe.hasMatch(id) || _mobileRe.hasMatch(id) ? null : 'Enter a valid email or 10-digit mobile number');
    setState(() {
      _identifierError = problem;
      _error = null;
    });
    if (problem != null) return;
    setState(() => _loading = true);
    try {
      final devOtp = await ref.read(authRepositoryProvider).requestPasswordReset(id);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _devOtp = devOtp;
        if (devOtp != null) _code.text = devOtp; // testing builds only, like sign-in OTPs
      });
    } catch (e) {
      if (!mounted) return;
      final err = ApiException.from(e);
      setState(() {
        _identifierError = err.fieldError('identifier');
        if (_identifierError == null) _error = err.message;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    final code = _code.text.trim();
    setState(() {
      _error = null;
      _codeError = RegExp(r'^[0-9]{6}$').hasMatch(code) ? null : 'Enter the 6-digit code';
      _passwordError = PasswordRules.error(_password.text);
      _confirmError = _password.text == _confirm.text ? null : 'Passwords do not match';
    });
    if (_codeError != null || _passwordError != null || _confirmError != null) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(identifier: _id, otp: code, newPassword: _password.text);
      if (mounted) Navigator.pop(context, _id);
    } catch (e) {
      if (!mounted) return;
      final err = ApiException.from(e);
      setState(() {
        _codeError = err.fieldError('otp');
        _passwordError = err.fieldError('newPassword');
        if (_codeError == null && _passwordError == null) _error = err.message;
      });
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
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _codeSent ? setState(() => _codeSent = false) : Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: Text(_codeSent ? 'Change email or number' : 'Back to log in'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (!_codeSent) ..._identifierStep() else ..._passwordStep(),
                  if (_error != null) ...[const SizedBox(height: 16), ErrorBanner(message: _error!)],
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _codeSent ? 'Reset password' : 'Send code',
                    loading: _loading,
                    onPressed: _codeSent ? _reset : _sendCode,
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Didn’t get a code? ', style: TextStyle(color: AppColors.ink)),
                        GestureDetector(
                          onTap: _loading ? null : _sendCode,
                          child: const Text('Resend',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _identifierStep() => [
        const AuthHeading(
          title: 'Forgot your password?',
          highlight: 'password',
          subtitle: 'Enter the email or mobile number on your account and we’ll send you a code to set a new password.',
        ),
        const SizedBox(height: 24),
        PillField(
          controller: _identifier,
          hint: 'Enter your Email or Mobile No.',
          icon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          errorText: _identifierError,
          onChanged: (_) {
            if (_identifierError != null) setState(() => _identifierError = null);
          },
        ),
      ];

  List<Widget> _passwordStep() => [
        AuthHeading(
          title: 'Set a new password',
          highlight: 'password',
          subtitle: 'If an account matches $_id, we’ve sent it a 6-digit code. It’s valid for 10 minutes.',
        ),
        const SizedBox(height: 24),
        PillField(
          controller: _code,
          hint: 'Enter 6-digit code',
          icon: Icons.password,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          errorText: _codeError,
        ),
        if (_devOtp != null) ...[
          const SizedBox(height: 8),
          Text('Dev code: $_devOtp', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
        const SizedBox(height: 20),
        const Text('Create a new password', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        const Text(PasswordRules.hint, style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        const SizedBox(height: 12),
        PillField(
          controller: _password,
          hint: 'New password',
          icon: Icons.lock_outline,
          obscure: true,
          errorText: _passwordError,
        ),
        const SizedBox(height: 16),
        PillField(
          controller: _confirm,
          hint: 'Confirm new password',
          icon: Icons.lock_outline,
          obscure: true,
          errorText: _confirmError,
        ),
      ];
}
