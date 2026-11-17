import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../navigation/push_guard.dart';
import '../theme/app_colors.dart';

/// "By continuing you are agreeing to our Terms of Service and Privacy Policy", under the
/// sign-up buttons (Figma: Sign Up 1-5 and 1-6, BUG-075). Each link opens its page.
class TermsNotice extends StatefulWidget {
  const TermsNotice({super.key});

  @override
  State<TermsNotice> createState() => _TermsNoticeState();
}

class _TermsNoticeState extends State<TermsNotice> {
  late final _terms = TapGestureRecognizer()..onTap = () => _open('Terms of Service');
  late final _privacy = TapGestureRecognizer()..onTap = () => _open('Privacy Policy');

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  void _open(String title) => context.pushPage(MaterialPageRoute(builder: (_) => LegalPage(title: title)));

  @override
  Widget build(BuildContext context) {
    const link = TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, decoration: TextDecoration.underline);
    return Text.rich(
      TextSpan(
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
        children: [
          const TextSpan(text: 'By continuing you are agreeing to our '),
          TextSpan(text: 'Terms of Service', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Terms of Service / Privacy Policy. The content isn't written yet, so the page says so.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Our $title will be published here soon.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ),
      ),
    );
  }
}
