import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/referrals/data/invite_rules.dart';
import 'package:link_local/features/referrals/data/referral_models.dart';
import 'package:link_local/features/referrals/data/referrals_repository.dart';
import 'package:link_local/features/referrals/presentation/referrals_screen.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

class _Launcher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final launched = <String>[];
  @override
  Future<bool> canLaunch(String url) async => true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Referrals implements ReferralsRepository {
  final invites = <({String? name, String? phone})>[];
  @override
  Future<void> sendInvite({String? name, String? phone, String? channel}) async =>
      invites.add((name: name, phone: phone));
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

ReferralSummary _summary(List<Map<String, dynamic>> referred) => ReferralSummary.fromJson({
  'inviteCode': 'AATH94894D',
  'invitedCount': referred.length,
  'dailyLimit': 500,
  'referred': referred,
});

Future<(_Referrals, _Launcher)> _open(WidgetTester tester, {List<Map<String, dynamic>> referred = const []}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _Referrals();
  final launcher = _Launcher();
  UrlLauncherPlatform.instance = launcher;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        referralsRepositoryProvider.overrideWithValue(repo),
        referralsProvider.overrideWith((ref) async => _summary(referred)),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ReferralsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (repo, launcher);
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Share'));
  await tester.pumpAndSettle();
}

Finder get _name => find.widgetWithText(TextField, 'Name (optional)');
Finder get _mobile => find.widgetWithText(TextField, 'Mobile number');
String _text(WidgetTester tester, Finder f) => tester.widget<TextField>(f).controller!.text;
VoidCallback? _sendButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Send via WhatsApp')).onPressed;

void main() {
  group('rules', () {
    test('mobile', () {
      expect(inviteMobileError('9876543210'), isNull);
      expect(inviteMobileError('+91 98765-43210'), isNull);
      expect(inviteMobileError('5876543210'), isNotNull, reason: 'Indian mobiles start 6–9');
      expect(inviteMobileError('98765'), isNotNull);
      expect(inviteMobileError('712345678999904940494040494'), isNotNull);
      expect(formatIndianMobile('9876543210'), '98765 43210');
    });
    test('name', () {
      expect(inviteNameError(''), isNull, reason: 'optional');
      expect(inviteNameError("Ravi K. D'Souza-Rao"), isNull);
      expect(inviteNameError('रवि कुमार'), isNull, reason: 'any alphabet');
      expect(inviteNameError('Ravi123'), 'Name can have letters and spaces only');
      expect(inviteNameError('a' * 51), 'Name can be at most 50 characters');
    });
  });

  group('invite sheet', () {
    testWidgets('the number stops at 10 digits (the long number from the report)', (tester) async {
      await _open(tester);
      await _openSheet(tester);
      await tester.enterText(_mobile, '712345678999904940494040494');
      await tester.pump();
      expect(_text(tester, _mobile), '7123456789');
    });

    testWidgets('a pasted "+91 98765-43210" becomes 9876543210, and is what gets sent', (tester) async {
      final (repo, launcher) = await _open(tester);
      await _openSheet(tester);
      await tester.enterText(_mobile, '+91 98765-43210');
      await tester.pump();
      expect(_text(tester, _mobile), '9876543210');

      await tester.tap(find.text('Send via WhatsApp'));
      await tester.pumpAndSettle();
      expect(repo.invites.single.phone, '9876543210');
      expect(launcher.launched.single, startsWith('https://wa.me/919876543210?text='));
    });

    testWidgets('a number starting with 5, or too short, shows the error and Send stays off', (tester) async {
      await _open(tester);
      await _openSheet(tester);
      expect(_sendButton(tester), isNull, reason: 'nothing entered yet');

      await tester.enterText(_mobile, '5876543210');
      await tester.pump();
      expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
      expect(_sendButton(tester), isNull);

      await tester.enterText(_mobile, '98765');
      await tester.pump();
      expect(_sendButton(tester), isNull);

      await tester.enterText(_mobile, '9876543210');
      await tester.pump();
      expect(find.text('Enter a valid 10-digit mobile number'), findsNothing);
      expect(_sendButton(tester), isNotNull);
    });

    testWidgets('the name stops at 50 characters and rejects digits', (tester) async {
      await _open(tester);
      await _openSheet(tester);
      await tester.enterText(_name, 'a' * 60);
      await tester.pump();
      expect(_text(tester, _name).length, 50);
      expect(find.text('50/50'), findsOneWidget, reason: 'the live counter');

      await tester.enterText(_name, 'Ravi123');
      await tester.enterText(_mobile, '9876543210');
      await tester.pump();
      expect(find.text('Name can have letters and spaces only'), findsOneWidget);
      expect(_sendButton(tester), isNull);
    });
  });

  group('people you referred', () {
    testWidgets('a number-only invite shows the number, not "Member"', (tester) async {
      await _open(tester, referred: [
        {'name': '9876543210', 'invitedName': null, 'phone': '9876543210', 'status': 'sent'},
      ]);
      expect(find.text('98765 43210'), findsOneWidget);
      expect(find.text('Member'), findsNothing);
    });

    testWidgets('a named invite shows the name, with the number beneath', (tester) async {
      await _open(tester, referred: [
        {'name': 'Ravi', 'invitedName': 'Ravi', 'phone': '9876543210', 'status': 'sent'},
      ]);
      expect(find.text('Ravi'), findsOneWidget);
      expect(find.textContaining('98765 43210 · Invite sent'), findsOneWidget);
    });

    testWidgets("someone who signed up with the code directly shows their name only", (tester) async {
      await _open(tester, referred: [
        {'name': 'Meena', 'profileName': 'Meena', 'status': 'complete_registration'},
      ]);
      expect(find.text('Meena'), findsOneWidget);
      expect(find.textContaining('Joined via your invite'), findsOneWidget);
      expect(find.textContaining('98'), findsNothing, reason: 'no phone shown');
    });
  });
}
