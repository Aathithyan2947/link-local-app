import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/auth_header.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';

/// Post-registration "thanks / verification pending" interstitial.
class VerificationHoldScreen extends ConsumerWidget {
  const VerificationHoldScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> continueOnApp() async {
      await ref.read(authControllerProvider.notifier).refreshUser();
      if (context.mounted) context.go(Routes.home);
    }

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
                  const _ShieldCheck(),
                  const SizedBox(height: 20),
                  const AuthHeading(
                    title: 'Thanks for joining LinkLocal',
                    highlight: 'LinkLocal',
                    subtitle:
                        "We’re reviewing your information to ensure a safe and trusted community for everyone on LinkLocal.",
                  ),
                  const SizedBox(height: 28),
                  _NextCard(),
                  const SizedBox(height: 28),
                  PrimaryButton(label: 'Continue on app', onPressed: continueOnApp),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShieldCheck extends StatelessWidget {
  const _ShieldCheck();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Icon(Icons.shield, size: 110, color: AppColors.primary),
          Icon(Icons.check, size: 48, color: Colors.white),
        ],
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.description, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('What happens next?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),
          const _Bullet('You’ll receive a notification once your profile has been approved.'),
          const _Bullet(
              'While we verify your profile, you can continue to browse through our service provider listings, interest groups and events in your area.'),
          const _Bullet.rich([
            _Span('For any urgent needs, feel free to contact us at '),
            _Span('+91 1234567890', green: true),
            _Span(' or '),
            _Span('example123@gmail.com', green: true),
            _Span('.'),
          ]),
        ],
      ),
    );
  }
}

class _Span {
  const _Span(this.text, {this.green = false});
  final String text;
  final bool green;
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text) : spans = null;
  const _Bullet.rich(this.spans) : text = null;
  final String? text;
  final List<_Span>? spans;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: text != null
                ? Text(text!, style: const TextStyle(color: AppColors.textSecondary, height: 1.4))
                : RichText(
                    text: TextSpan(
                      style: const TextStyle(color: AppColors.textSecondary, height: 1.4, fontSize: 14),
                      children: spans!
                          .map((s) => TextSpan(
                              text: s.text,
                              style: s.green
                                  ? const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)
                                  : null))
                          .toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
