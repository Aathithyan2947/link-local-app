import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';

class _Slide {
  const _Slide(this.image, this.title, this.highlight, this.subtitle);
  final String image;
  final String title; // contains [highlight] verbatim, rendered green
  final String highlight;
  final String subtitle;
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    _Slide('assets/images/onboarding_1.png', 'Welcome to your Local network', 'Local',
        'Find trusted people, services, events and opportunities around you.'),
    _Slide('assets/images/onboarding_2.png', 'Discover services nearby', 'services',
        'Search and connect with skilled people near you in seconds.'),
    _Slide('assets/images/onboarding_3.png', 'Trust build by community', 'community',
        'Reviews, ratings and local recommendations help you choose confidently.'),
    _Slide('assets/images/onboarding_4.png', 'Find what’s around you', 'around',
        'Whether you offer a service or need one, LinkLocal helps communities grow.'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    } else {
      context.go(Routes.register);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16, top: 4),
                child: TextButton(
                  onPressed: () => context.go(Routes.register),
                  child: const Text('Skip',
                      style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  return Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Image.asset(s.image, fit: BoxFit.contain),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          children: [
                            _title(s, theme),
                            const SizedBox(height: 12),
                            Text(s.subtitle,
                                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: active ? 24 : 8,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.divider,
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: PrimaryButton(
                label: _page == _slides.length - 1 ? 'Get Started' : 'Next',
                onPressed: _next,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already a member? ', style: TextStyle(color: AppColors.textSecondary)),
                  GestureDetector(
                    onTap: () => context.go(Routes.login),
                    child: const Text('Log in',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(_Slide s, ThemeData theme) {
    final style = theme.textTheme.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w700);
    final parts = s.title.split(s.highlight);
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: parts.first),
          TextSpan(text: s.highlight, style: const TextStyle(color: AppColors.primary)),
          if (parts.length > 1) TextSpan(text: parts[1]),
        ],
      ),
    );
  }
}
