import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/api_exception.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/core/validation/email_rules.dart';
import 'package:link_local/core/validation/password_rules.dart';
import 'package:link_local/core/widgets/error_banner.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/auth/data/auth_repository.dart';
import 'package:link_local/features/auth/presentation/forgot_password_screen.dart';
import 'package:link_local/features/auth/presentation/login_screen.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';
import 'package:link_local/features/profile/presentation/change_password_screen.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

class _SignedIn extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 5, userType: 'resident', email: 'asha@example.com', mobile: '9876543210'),
      );
}

/// Signed up with a mobile number only, so there's no email to send a reset code to.
class _MobileOnly extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 6, userType: 'resident', mobile: '9876543210'),
      );
}

/// A server that sends code 482913 and accepts only that code. Email login fails with
/// [loginError], so a test never gets as far as signing in.
class _Server implements AuthRepository {
  final requests = <String>[];
  final resets = <Map<String, String>>[];
  final logins = <String>[];
  Object loginError = ApiException('Invalid credentials', statusCode: 401);

  @override
  Future<AuthResult> login({required String identifier, required String password}) async {
    logins.add(identifier);
    throw loginError;
  }

  @override
  Future<String?> requestPasswordReset(String identifier) async {
    requests.add(identifier);
    return '482913';
  }

  @override
  Future<void> resetPassword({required String identifier, required String otp, required String newPassword}) async {
    if (otp != '482913') {
      throw ApiException('Invalid or expired code', statusCode: 400, details: {
        'otp': ['Invalid or expired code'],
      });
    }
    resets.add({'identifier': identifier, 'otp': otp, 'newPassword': newPassword});
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Profile implements ProfileRepository {
  int changes = 0;
  @override
  Future<void> changePassword({String? currentPassword, required String newPassword}) async => changes++;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<_Server> _pump(WidgetTester tester, Widget screen, {AuthController Function()? auth, _Profile? profile}) async {
  // Wide: the test font is wider than Poppins.
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final server = _Server();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(auth ?? _SignedOut.new),
      authRepositoryProvider.overrideWithValue(server),
      if (profile != null) profileRepositoryProvider.overrideWithValue(profile),
    ],
    child: MaterialApp(theme: AppTheme.light, home: screen),
  ));
  await tester.pumpAndSettle();
  return server;
}

Finder _field(String hint) => find.widgetWithText(TextField, hint);

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  test('BUG-066: the password policy matches the server, message for message', () {
    expect(PasswordRules.error('Ab1!'), 'Password must be at least 8 characters');
    expect(PasswordRules.error('password1!'), 'Password must include an uppercase letter');
    expect(PasswordRules.error('PASSWORD1!'), 'Password must include a lowercase letter');
    expect(PasswordRules.error('Password!!'), 'Password must include a number');
    expect(PasswordRules.error('Password12'), 'Password must include a special character');
    expect(PasswordRules.error('Passw0rd!'), isNull);
  });

  group('BUG-066: Forgot password', () {
    testWidgets('Login → Forgot password → code → new password → back on Login, filled in', (tester) async {
      final server = await _pump(tester, const LoginScreen());
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Enter your Email'), 'asha@example.com');
      await _tap(tester, 'Forgot password?');

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(tester.widget<TextField>(_field('Enter your Email')).controller!.text, 'asha@example.com',
          reason: 'the email typed on Login carries over');
      await _tap(tester, 'Send code');
      expect(server.requests, ['asha@example.com']);
      expect(find.text('Dev code: 482913'), findsOneWidget, reason: 'testing builds show the code, as for OTP sign-in');

      await tester.enterText(_field('New password'), 'password1!');
      await tester.enterText(_field('Confirm new password'), 'password1!');
      await _tap(tester, 'Reset password');
      expect(find.text('Password must include an uppercase letter'), findsOneWidget);
      expect(server.resets, isEmpty);

      await tester.enterText(_field('New password'), 'Passw0rd!');
      await tester.enterText(_field('Confirm new password'), 'Passw0rd!x');
      await _tap(tester, 'Reset password');
      expect(find.text('Passwords do not match'), findsOneWidget);

      await tester.enterText(_field('Confirm new password'), 'Passw0rd!');
      await _tap(tester, 'Reset password');
      expect(server.resets.single, {'identifier': 'asha@example.com', 'otp': '482913', 'newPassword': 'Passw0rd!'});
      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(find.text('Password updated. Log in with your new password.'), findsOneWidget);
      expect(tester.widget<TextField>(_field('Enter your Email')).controller!.text, 'asha@example.com');
    });

    testWidgets("a wrong code says so under the code field", (tester) async {
      final server = await _pump(tester, const ForgotPasswordScreen(identifier: 'asha@example.com'));
      await _tap(tester, 'Send code');
      await tester.enterText(_field('Enter 6-digit code'), '000000');
      await tester.enterText(_field('New password'), 'Passw0rd!');
      await tester.enterText(_field('Confirm new password'), 'Passw0rd!');
      await _tap(tester, 'Reset password');
      expect(find.text('Invalid or expired code'), findsOneWidget);
      expect(server.resets, isEmpty);
    });

    testWidgets('BUG-106: an email is required before sending a code, not a mobile number', (tester) async {
      final server = await _pump(tester, const ForgotPasswordScreen());
      await _tap(tester, 'Send code');
      expect(find.text('Enter your email'), findsOneWidget);
      await tester.enterText(_field('Enter your Email'), 'asha@');
      await _tap(tester, 'Send code');
      expect(find.text('Enter a valid email address'), findsOneWidget);
      await tester.enterText(_field('Enter your Email'), '9876543210');
      await _tap(tester, 'Send code');
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets("Change Password's “Forget password?” opens it for the signed-in account", (tester) async {
      await _pump(tester, const ChangePasswordScreen(), auth: _SignedIn.new, profile: _Profile());
      await _tap(tester, 'Forget password?');
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(tester.widget<TextField>(_field('Enter your Email')).controller!.text, 'asha@example.com');
    });

    testWidgets("BUG-106: Change Password's “Forget password?” explains that a reset needs an email", (tester) async {
      await _pump(tester, const ChangePasswordScreen(), auth: _MobileOnly.new, profile: _Profile());
      await _tap(tester, 'Forget password?');
      expect(find.byType(ForgotPasswordScreen), findsNothing, reason: "the code can't go to a mobile number");
      expect(find.text('Resetting your password needs an email on your account. Add one in My Email first.'),
          findsOneWidget);
    });

    testWidgets('Change Password uses the sign-up policy, not "6 characters"', (tester) async {
      final profile = _Profile();
      await _pump(tester, const ChangePasswordScreen(), auth: _SignedIn.new, profile: profile);
      await tester.enterText(_field('Enter new password'), 'abcdef');
      await tester.enterText(_field('Confirm new password'), 'abcdef');
      await _tap(tester, 'Confirm');
      expect(find.text('Password must be at least 8 characters'), findsOneWidget);
      expect(profile.changes, 0);
    });
  });

  group('BUG-106: the Email tab takes an email, not a phone number', () {
    test('EmailRules', () {
      expect(EmailRules.isValid('asha@example.com'), isTrue);
      expect(EmailRules.isValid(' asha@example.com '), isTrue);
      expect(EmailRules.isValid("o'brien@example.com"), isTrue, reason: 'the server accepts it');
      expect(EmailRules.isValid('9876543210'), isFalse);
      expect(EmailRules.isValid('asha@'), isFalse);
    });

    Future<_Server> pumpEmailTab(WidgetTester tester) async {
      final server = await _pump(tester, const LoginScreen());
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      return server;
    }

    String? emailError(WidgetTester tester) => tester.widget<TextField>(_field('Enter your Email')).decoration!.errorText;

    testWidgets('a phone number is flagged under the field and never sent', (tester) async {
      final server = await pumpEmailTab(tester);
      await tester.enterText(_field('Enter your Email'), '9876543210');
      await tester.enterText(_field('Enter your Password'), 'Passw0rd!');
      await _tap(tester, 'Log in');

      expect(emailError(tester), 'Enter a valid email address');
      expect(find.byType(ErrorBanner), findsNothing);
      expect(server.logins, isEmpty);

      await tester.enterText(_field('Enter your Email'), '98765');
      await tester.pump();
      expect(emailError(tester), isNull, reason: 'editing the field clears it');
    });

    testWidgets('a valid email is sent; a server email message lands under the field', (tester) async {
      final server = await pumpEmailTab(tester);
      server.loginError = ApiException('Enter a valid email address', statusCode: 400, details: {
        'identifier': ['Enter a valid email address'],
      });
      await tester.enterText(_field('Enter your Email'), ' asha@example.c ');
      await tester.enterText(_field('Enter your Password'), 'Passw0rd!');
      await _tap(tester, 'Log in');

      expect(server.logins, ['asha@example.c']);
      expect(emailError(tester), 'Enter a valid email address');
      expect(find.byType(ErrorBanner), findsNothing);
    });

    testWidgets('wrong credentials still show the banner', (tester) async {
      final server = await pumpEmailTab(tester);
      await tester.enterText(_field('Enter your Email'), 'asha@example.com');
      await tester.enterText(_field('Enter your Password'), 'wrong');
      await _tap(tester, 'Log in');

      expect(server.logins, ['asha@example.com']);
      expect(emailError(tester), isNull);
      expect(find.widgetWithText(ErrorBanner, 'Invalid credentials'), findsOneWidget);
    });
  });
}
