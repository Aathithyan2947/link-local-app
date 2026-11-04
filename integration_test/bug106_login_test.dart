// BUG-106: Login's Email tab and Forgot password take an email only. A mobile number there is
// refused under the field before anything is sent (mobile numbers sign in with an OTP on the
// Mobile no. tab). A valid email and password log in, in any letter case.
//
// Run: see integration_test/support/harness.dart.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/validation/email_rules.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/presentation/forgot_password_screen.dart';
import 'package:link_local/features/auth/presentation/login_screen.dart';
import 'package:link_local/features/home/presentation/home_shell.dart';

import 'support/harness.dart';

void main() {
  initIntegrationTest();
  final api = TestApi();

  /// A verified resident with both an email and a mobile number on the account.
  Future<SeededUser> newAccount(String tag) {
    final s = uniqueStamp();
    return api.createMember(
      name: 'Login ${s.letters}',
      email: 'bug106.$tag.${s.digits}@example.com',
      mobile: uniqueMobile(),
    );
  }

  /// The message under the field whose placeholder is [hint], if any.
  Finder errorUnder(String hint, String message) =>
      find.descendant(of: pillField(hint), matching: find.text(message));

  group('BUG-106 login: email only', () {
    testWidgets('a mobile number in the Email field is refused under the field and nothing is sent',
        (tester) async {
      final user = await newAccount('phone');
      await launchApp(tester);
      final requests = recordAppRequests(tester);

      await openEmailTab(tester);
      await typeInto(tester, pillField('Enter your Email'), user.mobile!);
      await typeInto(tester, pillField('Enter your Password'), user.password);
      await tapOn(tester, find.widgetWithText(ElevatedButton, 'Log in'));
      await pumpFor(tester, const Duration(seconds: 2));

      expect(errorUnder('Enter your Email', EmailRules.invalid), findsOneWidget,
          reason: 'the email check shows under the Email field');
      expect(find.text(EmailRules.invalid), findsOneWidget, reason: 'and nowhere else (no banner)');
      expect(requests.sent('POST', '/auth/login'), isFalse, reason: 'nothing is sent: $requests');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(appContainer(tester).read(authControllerProvider).isAuthenticated, isFalse);
      await screenshot(tester, 'bug106_phone_in_email_field');

      // Editing the field clears the message.
      await typeInto(tester, pillField('Enter your Email'), user.email);
      expect(find.text(EmailRules.invalid), findsNothing);
    });

    testWidgets('a valid email and password log in, whatever the letter case', (tester) async {
      final user = await newAccount('ok');
      await launchApp(tester);
      final requests = recordAppRequests(tester);

      await loginWithEmail(tester, user.email.toUpperCase(), user.password);

      expect(find.byType(HomeShell), findsOneWidget);
      expect(requests.sent('POST', '/auth/login'), isTrue);
      final auth = appContainer(tester).read(authControllerProvider);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.user?.id, user.userId, reason: 'signed in as the account with that email');
      expect(auth.user?.email, user.email);
      await screenshot(tester, 'bug106_email_login_home');
    });

    testWidgets('a wrong password is still told apart from a bad email', (tester) async {
      final user = await newAccount('wrongpw');
      await launchApp(tester);

      await loginWithEmail(tester, user.email, 'Wrong@12345', expectHome: false);
      await pumpUntil(tester, find.textContaining('Invalid credentials'),
          reason: 'the server refuses the password with a banner');
      expect(find.text(EmailRules.invalid), findsNothing, reason: 'the email itself is fine');
      expect(find.byType(HomeShell), findsNothing);
    });
  });

  group('BUG-106 forgot password: email only', () {
    testWidgets('a mobile number is refused under the field and no code is requested', (tester) async {
      final user = await newAccount('forgotphone');
      await launchApp(tester);
      final requests = recordAppRequests(tester);

      await openEmailTab(tester);
      await typeInto(tester, pillField('Enter your Email'), user.mobile!);
      await tapOn(tester, find.text('Forgot password?'), settle: const Duration(milliseconds: 800));
      await pumpUntil(tester, find.byType(ForgotPasswordScreen));
      expect(find.text('Forgot your password?', findRichText: true), findsOneWidget);
      expect(find.textContaining('Log in with an OTP on the Mobile no. tab'), findsOneWidget,
          reason: 'it says where mobile accounts go instead');

      // The phone number typed on Login comes along; Send code refuses it.
      expect(find.descendant(of: pillField('Enter your Email'), matching: find.text(user.mobile!)), findsOneWidget);
      await tapOn(tester, find.widgetWithText(ElevatedButton, 'Send code'));
      await pumpFor(tester, const Duration(seconds: 2));

      expect(errorUnder('Enter your Email', EmailRules.invalid), findsOneWidget);
      expect(requests.sent('POST', '/auth/password/forgot'), isFalse, reason: 'nothing is sent: $requests');
      expect(find.text('Set a new password', findRichText: true), findsNothing, reason: 'still on the email step');
      await screenshot(tester, 'bug106_forgot_phone_refused');
    });

    testWidgets('an email gets a code, sets a new password, and logs in with it', (tester) async {
      final user = await newAccount('forgotok');
      const newPassword = 'Fresh@54321';
      await launchApp(tester);

      await openEmailTab(tester);
      await tapOn(tester, find.text('Forgot password?'), settle: const Duration(milliseconds: 800));
      await pumpUntil(tester, find.byType(ForgotPasswordScreen));
      // Mixed case on purpose: the account is found in any letter case.
      final typed = user.email.replaceFirst('bug106', 'BUG106');
      await typeInto(tester, pillField('Enter your Email'), typed);
      await tapOn(tester, find.widgetWithText(ElevatedButton, 'Send code'));
      await pumpUntil(tester, find.text('Set a new password', findRichText: true), reason: 'the code step opens');
      expect(find.textContaining('Dev code: '), findsOneWidget, reason: 'the test backend exposes the code');

      await typeInto(tester, pillField('New password'), newPassword);
      await typeInto(tester, pillField('Confirm new password'), newPassword);
      await tapOn(tester, find.widgetWithText(ElevatedButton, 'Reset password'));
      await pumpUntil(tester, find.text('Password updated. Log in with your new password.'),
          reason: 'back on Login with a confirmation');
      await pumpUntilGone(tester, find.byType(ForgotPasswordScreen), reason: 'the reset screen closes');
      expect(find.descendant(of: pillField('Enter your Email'), matching: find.text(typed)), findsOneWidget,
          reason: 'the email comes back filled in');
      await screenshot(tester, 'bug106_forgot_reset_done');

      await typeInto(tester, pillField('Enter your Password'), newPassword);
      await tapOn(tester, find.widgetWithText(ElevatedButton, 'Log in'));
      await pumpUntil(tester, find.byType(HomeShell), reason: 'the new password logs in');
      expect(appContainer(tester).read(authControllerProvider).user?.id, user.userId);

      expect((await api.login(user.email, user.password)).statusCode, 401, reason: 'the old password is gone');
    });
  });

  group('BUG-106 backend', () {
    testWidgets('login, forgot and reset take an email only, in any letter case', (tester) async {
      final user = await newAccount('api');
      Map<String, dynamic> body(Response<dynamic> r) => (r.data as Map).cast<String, dynamic>();

      final byPhone = await api.login(user.mobile!, user.password);
      expect(byPhone.statusCode, 400, reason: 'login by mobile number: ${byPhone.data}');
      expect(body(byPhone)['details']['identifier'], [EmailRules.invalid]);

      final upper = await api.login(user.email.toUpperCase(), user.password);
      expect(upper.statusCode, 200, reason: 'login by email in capitals: ${upper.data}');
      expect(body(upper)['data']['user']['id'], user.userId);

      final forgotPhone = await api.send('POST', '/auth/password/forgot', body: {'identifier': user.mobile});
      expect(forgotPhone.statusCode, 400, reason: 'forgot by mobile number: ${forgotPhone.data}');
      expect(body(forgotPhone)['details']['identifier'], [EmailRules.invalid]);

      final forgot = await api.send('POST', '/auth/password/forgot', body: {'identifier': user.email.toUpperCase()});
      expect(forgot.statusCode, 200, reason: 'forgot by email in capitals: ${forgot.data}');
      final code = body(forgot)['data']['devOtp'] as String?;
      expect(code, isNotNull, reason: 'a code was issued for the account');

      final resetPhone = await api.send('POST', '/auth/password/reset',
          body: {'identifier': user.mobile, 'otp': code, 'newPassword': 'Other@12345'});
      expect(resetPhone.statusCode, 400, reason: 'reset by mobile number: ${resetPhone.data}');
      expect(body(resetPhone)['details']['identifier'], [EmailRules.invalid]);

      final reset = await api.send('POST', '/auth/password/reset',
          body: {'identifier': user.email.toUpperCase(), 'otp': code, 'newPassword': 'Other@12345'});
      expect(reset.statusCode, 200, reason: 'reset by email in capitals: ${reset.data}');
      expect((await api.login(user.email, 'Other@12345')).statusCode, 200);
    });
  });
}
