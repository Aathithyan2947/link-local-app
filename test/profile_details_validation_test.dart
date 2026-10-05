import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/business/data/business_repository.dart';
import 'package:link_local/features/business/data/profile_limits.dart';
import 'package:link_local/features/business/data/rate_models.dart';
import 'package:link_local/features/business/presentation/setup/sp_setup_wizard_screen.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';

/// Records what "Set up your profile" saves; `profileError` makes the profile save fail the
/// way the server would.
class _FakeBusiness implements BusinessRepository {
  final profileSaves = <Map<String, dynamic>>[];
  DioException? profileError;

  @override
  Future<void> updateProfile(Map<String, dynamic> data) async {
    if (profileError != null) throw profileError!;
    profileSaves.add(data);
  }

  @override
  Future<void> setProfessions(List<Map<String, dynamic>> professions) async {}
  @override
  Future<void> setRates(List<SpRate> rates) async {}
  @override
  Future<List<SpRate>> myRates() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

DioException _serverRejects(int status, Map<String, dynamic> body) {
  final req = RequestOptions(path: '/profiles/me');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: status, data: body),
    type: DioExceptionType.badResponse,
  );
}

Future<void> _open(WidgetTester tester, _FakeBusiness repo) async {
  tester.view.physicalSize = const Size(1170, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        businessRepositoryProvider.overrideWithValue(repo),
        myProfileProvider.overrideWith((ref) async => ProfileDetail.fromJson({'id': 60, 'name': 'Asha'})),
      ],
      // A service provider (not menu-based): the step also has the charges.
      child: const MaterialApp(home: SpSetupWizardScreen(initialName: 'Asha')),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

void main() {
  group('ProfileLimits', () {
    test('name', () {
      expect(ProfileLimits.nameError('  '), 'Name is required');
      expect(ProfileLimits.nameError('a' * 100), isNull);
      expect(ProfileLimits.nameError('a' * 101), 'Name can be at most 100 characters');
    });
    test('title, about', () {
      expect(ProfileLimits.titleError('t' * 81), 'Professional title can be at most 80 characters');
      expect(ProfileLimits.aboutError('a' * 2001), 'About can be at most 2000 characters');
      expect(ProfileLimits.aboutError('a' * 2000), isNull);
    });
    test('experience and charges', () {
      expect(ProfileLimits.experienceError(''), isNull);
      expect(ProfileLimits.experienceError('81'), 'Years of experience must be between 0 and 80');
      expect(ProfileLimits.rateError(''), isNull);
      expect(ProfileLimits.rateError('1000000'), isNull);
      expect(ProfileLimits.rateError('2000000'), 'Charge can be at most ₹10,00,000');
      expect(ProfileLimits.rateError('0'), 'Charge must be greater than 0');
    });
  });

  testWidgets('every field over its limit shows its own message, and nothing is saved', (tester) async {
    final repo = _FakeBusiness();
    await _open(tester, repo);

    await tester.enterText(_field('Your Name'), 'a' * 101);
    await tester.enterText(_field('Your professional title'), 't' * 81);
    await tester.enterText(_field('Years of experience'), '81');
    await tester.enterText(_field('About yourself'), 'b' * 2001);
    await tester.enterText(_field('Hourly'), '2000000');
    await _next(tester);

    expect(find.text('Name can be at most 100 characters'), findsOneWidget);
    expect(find.text('Professional title can be at most 80 characters'), findsOneWidget);
    expect(find.text('Years of experience must be between 0 and 80'), findsOneWidget);
    expect(find.text('About can be at most 2000 characters'), findsOneWidget);
    expect(find.text('Charge can be at most ₹10,00,000'), findsOneWidget);
    expect(find.text('101/100'), findsOneWidget, reason: 'the live counter shows how far over it is');
    expect(find.text('Could not save. Please try again.'), findsNothing, reason: 'no generic toast');
    expect(repo.profileSaves, isEmpty);
    expect(_field('Your Name'), findsOneWidget, reason: 'stays on the step');
  });

  testWidgets('fixing a field clears its message; once all fit, Next saves', (tester) async {
    final repo = _FakeBusiness();
    await _open(tester, repo);
    await tester.enterText(_field('Your Name'), 'a' * 101);
    await _next(tester);
    expect(find.text('Name can be at most 100 characters'), findsOneWidget);

    await tester.enterText(_field('Your Name'), 'Asha Rao');
    await tester.pumpAndSettle();
    expect(find.text('Name can be at most 100 characters'), findsNothing);
    await _next(tester);
    expect(repo.profileSaves.single['name'], 'Asha Rao');
  });

  testWidgets('an empty name says it is required, under the field', (tester) async {
    final repo = _FakeBusiness();
    await _open(tester, repo);
    await tester.enterText(_field('Your Name'), '');
    await _next(tester);
    expect(find.text('Name is required'), findsOneWidget);
    expect(repo.profileSaves, isEmpty);
  });

  testWidgets("the server's field message lands under that field", (tester) async {
    final repo = _FakeBusiness()
      ..profileError = _serverRejects(400, {
        'success': false,
        'message': 'Validation failed',
        'details': {
          'aboutMe': ['About can be at most 2000 characters'],
        },
      });
    await _open(tester, repo);
    await _next(tester);
    expect(find.text('About can be at most 2000 characters'), findsOneWidget);
    expect(find.text('Could not save. Please try again.'), findsNothing);
  });

  testWidgets('a real server failure still shows the generic message', (tester) async {
    final repo = _FakeBusiness()
      ..profileError = _serverRejects(500, {'success': false, 'message': 'Internal server error'});
    await _open(tester, repo);
    await _next(tester);
    expect(find.text('Could not save. Please try again.'), findsOneWidget);
  });
}
