import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/presentation/otp_screen.dart';
import 'package:link_local/features/auth/presentation/register_screen.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  // Wide: the test font is wider than Poppins (see auth_forms_test).
  tester.view.physicalSize = const Size(1800, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [authControllerProvider.overrideWith(_SignedOut.new)],
    child: MaterialApp(theme: AppTheme.light, home: screen),
  ));
  await tester.pumpAndSettle();
}

Finder get _notice => find.textContaining('By continuing you are agreeing to our', findRichText: true);

void main() {
  group('BUG-075: Terms of Service and Privacy Policy links', () {
    testWidgets('the email sign-up form shows them under Continue', (tester) async {
      await _pump(tester, const RegisterScreen());
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      expect(_notice, findsOneWidget);
    });

    testWidgets('the mobile tab does not (the code screen shows them, as in the Figma)', (tester) async {
      await _pump(tester, const RegisterScreen());
      expect(_notice, findsNothing);
    });

    testWidgets('the sign-up code screen shows them; the log-in one does not', (tester) async {
      await _pump(tester, const OtpScreen(args: OtpArgs(mobile: '9876543210', purpose: 'registration')));
      expect(_notice, findsOneWidget);

      await _pump(tester, const OtpScreen(args: OtpArgs(mobile: '9876543210', purpose: 'login')));
      expect(_notice, findsNothing);
    });

    testWidgets('each link opens its page (placeholder until the content is ready)', (tester) async {
      await _pump(tester, const RegisterScreen());
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();

      await tester.tapOnText(find.textRange.ofSubstring('Terms of Service'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Terms of Service'), findsOneWidget);

      Navigator.of(tester.element(find.byType(AppBar))).pop();
      await tester.pumpAndSettle();
      await tester.tapOnText(find.textRange.ofSubstring('Privacy Policy'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Privacy Policy'), findsOneWidget);
    });
  });
}
