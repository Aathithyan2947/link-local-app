import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/api_exception.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/core/widgets/error_banner.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/presentation/login_screen.dart';
import 'package:link_local/features/auth/presentation/register_screen.dart';

/// Signed out; records sign-up calls instead of hitting the network. Each call throws so the
/// screen never tries to navigate (there's no router here).
class _FakeAuth extends AuthController {
  static int otpRequests = 0;
  static int registrations = 0;
  static Object failWith = ApiException('stop');

  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);

  @override
  Future<String?> requestOtp({String? mobile, String? email, required String purpose, String? name}) async {
    otpRequests++;
    throw failWith;
  }

  @override
  Future<void> register({
    required String name,
    required String password,
    String? email,
    String? mobile,
    String userType = 'resident',
    String? referralCode,
    int? referralSourceId,
  }) async {
    registrations++;
    throw failWith;
  }
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  // Wide: the test font is wider than Poppins, and the "Already have an Account? Log in"
  // footer would overflow at a phone width.
  tester.view.physicalSize = const Size(1800, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  _FakeAuth.otpRequests = 0;
  _FakeAuth.registrations = 0;
  _FakeAuth.failWith = ApiException('stop');
  await tester.pumpWidget(ProviderScope(
    overrides: [authControllerProvider.overrideWith(_FakeAuth.new)],
    child: MaterialApp(theme: AppTheme.light, home: screen),
  ));
  await tester.pumpAndSettle();
}

bool _obscured(WidgetTester tester, String hint) =>
    tester.widget<TextField>(find.widgetWithText(TextField, hint)).obscureText;

Finder get _nameField => find.widgetWithText(TextField, 'Enter your Full Name');

void main() {
  group('BUG-063: password fields have a show/hide eye', () {
    testWidgets('on Login (Email tab)', (tester) async {
      await _pump(tester, const LoginScreen());
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();

      expect(_obscured(tester, 'Enter your Password'), isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(_obscured(tester, 'Enter your Password'), isFalse);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(_obscured(tester, 'Enter your Password'), isTrue);
    });

    testWidgets('on Sign Up, each password field toggles on its own', (tester) async {
      await _pump(tester, const RegisterScreen());
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();

      expect(_obscured(tester, 'Create your Password'), isTrue);
      expect(_obscured(tester, 'Confirm your Password'), isTrue);
      await tester.tap(find.byTooltip('Show password').first);
      await tester.pump();
      expect(_obscured(tester, 'Create your Password'), isFalse);
      expect(_obscured(tester, 'Confirm your Password'), isTrue);
    });
  });

  group('BUG-064/065: sign-up name rules', () {
    testWidgets('digits and symbols are not accepted', (tester) async {
      await _pump(tester, const RegisterScreen());
      await tester.enterText(_nameField, 'Ravi123@#');
      await tester.pump();
      expect(tester.widget<TextField>(_nameField).controller!.text, 'Ravi');
    });

    testWidgets('typing or pasting stops at 100 characters', (tester) async {
      await _pump(tester, const RegisterScreen());
      await tester.enterText(_nameField, 'A' * 150);
      await tester.pump();
      expect(tester.widget<TextField>(_nameField).controller!.text, 'A' * 100);
      expect(find.text('Name can be at most 100 characters'), findsNothing, reason: 'nothing to complain about');

      await tester.enterText(find.widgetWithText(TextField, 'Enter your 10-digit Mobile No.'), '9876543210');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();
      expect(_FakeAuth.otpRequests, 1, reason: 'a 100-character name is valid');
    });

    testWidgets('an empty or one-letter name is flagged under the field', (tester) async {
      await _pump(tester, const RegisterScreen());
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your name'), findsOneWidget);
      expect(find.byType(ErrorBanner), findsNothing);

      await tester.enterText(_nameField, 'R');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();
      expect(find.text('Name must be at least 2 characters'), findsOneWidget);
      expect(_FakeAuth.otpRequests, 0);
    });

    testWidgets("the server's name message lands under the Name field", (tester) async {
      await _pump(tester, const RegisterScreen());
      _FakeAuth.failWith = ApiException('Name can be at most 100 characters', statusCode: 400, details: {
        'name': ['Name can be at most 100 characters'],
      });
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      await tester.enterText(_nameField, 'Ravi Kumar');
      await tester.enterText(find.widgetWithText(TextField, 'Enter your Email'), 'ravi@example.com');
      await tester.enterText(find.widgetWithText(TextField, 'Create your Password'), 'Passw0rd!');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm your Password'), 'Passw0rd!');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(_FakeAuth.registrations, 1);
      expect(find.text('Name can be at most 100 characters'), findsOneWidget);
      expect(find.byType(ErrorBanner), findsNothing);
    });
  });

  testWidgets('BUG-094: the mobile placeholder matches the "Mobile no." tab', (tester) async {
    await _pump(tester, const RegisterScreen());
    expect(find.text('Mobile no.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Enter your 10-digit Mobile No.'), findsOneWidget);
    expect(find.textContaining('Phone No.'), findsNothing);

    await _pump(tester, const LoginScreen());
    expect(find.widgetWithText(TextField, 'Enter your 10-digit Mobile No.'), findsOneWidget);
  });
}
