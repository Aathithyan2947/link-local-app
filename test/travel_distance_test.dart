import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/business/data/availability_models.dart';
import 'package:link_local/features/business/data/business_repository.dart';
import 'package:link_local/features/business/data/rate_models.dart';
import 'package:link_local/features/business/presentation/setup/sp_setup_wizard_screen.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';

/// Records what the wizard saves; `availabilityError` makes the availability save fail the
/// way the server would.
class _FakeBusiness implements BusinessRepository {
  final availabilitySaves = <Map<String, dynamic>>[];
  DioException? availabilityError;

  @override
  Future<void> updateProfile(Map<String, dynamic> data) async {}
  @override
  Future<void> setProfessions(List<Map<String, dynamic>> professions) async {}
  @override
  Future<void> setRates(List<SpRate> rates) async {}
  @override
  Future<List<SpRate>> myRates() async => const [];

  @override
  Future<void> setAvailability(Map<String, dynamic> data) async {
    if (availabilityError != null) throw availabilityError!;
    availabilitySaves.add(data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

DioException _serverRejects(int status, Map<String, dynamic> body) {
  final req = RequestOptions(path: '/profiles/me/availability');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: status, data: body),
    type: DioExceptionType.badResponse,
  );
}

/// Opens the wizard, passes step 1 (details), and lands on Availability & Timing.
Future<void> _toAvailabilityStep(WidgetTester tester, _FakeBusiness repo) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        businessRepositoryProvider.overrideWithValue(repo),
        myProfileProvider.overrideWith((ref) async => ProfileDetail.fromJson({'id': 60, 'name': 'Asha'})),
      ],
      child: const MaterialApp(home: SpSetupWizardScreen(initialName: 'Asha', hasDateBooking: true)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
  expect(find.text('Maximum distance can you travel (km)'), findsOneWidget);
}

Finder get _distanceField => find.widgetWithText(TextFormField, 'Maximum distance can you travel (km)');

void main() {
  group('travelDistanceError', () {
    test('empty is allowed (the distance is optional)', () => expect(travelDistanceError('  '), isNull));
    test('within the limit', () {
      expect(travelDistanceError('1'), isNull);
      expect(travelDistanceError('100'), isNull);
      expect(travelDistanceError('12.5'), isNull);
    });
    test('over the limit', () {
      expect(travelDistanceError('1000'), 'Maximum travel distance cannot exceed 100 km');
      expect(travelDistanceError('100.5'), 'Maximum travel distance cannot exceed 100 km');
    });
    test('zero or not a number', () {
      expect(travelDistanceError('0'), 'Enter a distance greater than 0');
      expect(travelDistanceError('.'), 'Enter a distance greater than 0');
    });
  });

  testWidgets('1000 km shows the message under the field and saves nothing', (tester) async {
    final repo = _FakeBusiness();
    await _toAvailabilityStep(tester, repo);

    await tester.enterText(_distanceField, '1000');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Maximum travel distance cannot exceed 100 km'), findsOneWidget);
    expect(find.text('Could not save. Please try again.'), findsNothing, reason: 'no generic toast');
    expect(repo.availabilitySaves, isEmpty, reason: 'nothing is saved');
    expect(_distanceField, findsOneWidget, reason: 'stays on the step');

    // Fixing it clears the message as they type, and Next then saves.
    await tester.enterText(_distanceField, '50');
    await tester.pumpAndSettle(); // the error fades out
    expect(find.text('Maximum travel distance cannot exceed 100 km'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(repo.availabilitySaves.single['maxTravelKm'], 50);
  });

  testWidgets('0 asks for a distance greater than 0', (tester) async {
    final repo = _FakeBusiness();
    await _toAvailabilityStep(tester, repo);
    await tester.enterText(_distanceField, '0');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a distance greater than 0'), findsOneWidget);
    expect(repo.availabilitySaves, isEmpty);
  });

  testWidgets('an empty distance still saves', (tester) async {
    final repo = _FakeBusiness();
    await _toAvailabilityStep(tester, repo);
    await tester.enterText(_distanceField, '');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(repo.availabilitySaves, hasLength(1));
    expect(repo.availabilitySaves.single.containsKey('maxTravelKm'), isFalse);
  });

  testWidgets("the server's field message lands under the field, not in a generic toast", (tester) async {
    final repo = _FakeBusiness()
      ..availabilityError = _serverRejects(400, {
        'success': false,
        'message': 'Validation failed',
        'details': {
          'maxTravelKm': ['Maximum travel distance cannot exceed 100 km'],
        },
      });
    await _toAvailabilityStep(tester, repo);
    await tester.enterText(_distanceField, '60'); // passes the app's check; the server says no
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Maximum travel distance cannot exceed 100 km'), findsOneWidget);
    expect(find.text('Could not save. Please try again.'), findsNothing);
  });

  testWidgets("another validation reason from the server is shown as is", (tester) async {
    final repo = _FakeBusiness()
      ..availabilityError = _serverRejects(400, {
        'success': false,
        'message': 'Validation failed',
        'details': {
          'endTime': ['End time must be after start time'],
        },
      });
    await _toAvailabilityStep(tester, repo);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('End time must be after start time'), findsOneWidget);
  });

  testWidgets('a real server failure still shows the generic message', (tester) async {
    final repo = _FakeBusiness()
      ..availabilityError = _serverRejects(500, {'success': false, 'message': 'Internal server error'});
    await _toAvailabilityStep(tester, repo);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save. Please try again.'), findsOneWidget);
  });
}
