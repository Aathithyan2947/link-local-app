import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/api_exception.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/business/data/availability_models.dart';
import 'package:link_local/features/services/data/service_profile_repository.dart';
import 'package:link_local/features/services/presentation/category_fields_form_screen.dart';

/// Signed in as nobody in particular, without token storage or the network.
class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

/// The Travel category with one admin-defined "Maximum distance can you travel" field.
class _FakeServiceProfile implements ServiceProfileRepository {
  _FakeServiceProfile({this.saved, this.saveError});
  final String? saved;
  final ApiException? saveError;
  final saves = <List<Map<String, dynamic>>>[];

  @override
  Future<List<CustomField>> getCustomFields() async => [
    CustomField.fromJson({
      'fieldId': 363,
      'category': 'travel',
      'fieldName': 'Maximum distance can you travel',
      'fieldType': 'number',
      'value': saved,
    }),
  ];

  @override
  Future<void> saveCustomFields(List<Map<String, dynamic>> values) async {
    if (saveError != null) throw saveError!;
    saves.add(values);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<void> _open(WidgetTester tester, _FakeServiceProfile repo) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        serviceProfileRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        home: CategoryFieldsFormScreen(category: 'travel', categoryLabel: 'Travel'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _field => find.byType(TextField);

void main() {
  group('reading a saved distance', () {
    test('accepts older answers with a unit', () {
      expect(parseTravelKm('10 km'), 10);
      expect(parseTravelKm('15 kms'), 15);
      expect(parseTravelKm('5km'), 5);
      expect(parseTravelKm('12.5'), 12.5);
      expect(parseTravelKm('about ten'), isNull);
    });
    test('the profile shows only distances within the limit', () {
      expect(displayableTravelKm('10 km'), 10);
      expect(displayableTravelKm('1000000'), isNull, reason: 'no "Travels up to 1000000 km"');
      expect(displayableTravelKm('9999999999999999999999'), isNull);
      expect(displayableTravelKm(null), isNull);
    });
    test('recognises the distance field the way the profile page does', () {
      expect(
        isTravelDistanceField(category: 'travel', fieldName: 'Maximum distance can you travel', fieldType: 'number'),
        isTrue,
      );
      expect(isTravelDistanceField(category: 'travel', fieldName: 'Willing to travel', fieldType: 'text'), isFalse);
      expect(isTravelDistanceField(category: 'payment', fieldName: 'Distance fee', fieldType: 'number'), isFalse);
    });
  });

  testWidgets('1000000 in the Travel form shows the message under the field and saves nothing', (tester) async {
    final repo = _FakeServiceProfile();
    await _open(tester, repo);
    expect(find.text('In km, up to 100'), findsOneWidget);

    await tester.enterText(_field, '1000000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Maximum travel distance cannot exceed 100 km'), findsOneWidget);
    expect(repo.saves, isEmpty);

    await tester.enterText(_field, '25');
    await tester.pumpAndSettle();
    expect(find.text('Maximum travel distance cannot exceed 100 km'), findsNothing, reason: 'clears as it is fixed');
  });

  testWidgets('an older "10 km" answer loads as 10, so it can be edited', (tester) async {
    await _open(tester, _FakeServiceProfile(saved: '10 km'));
    expect(tester.widget<TextField>(_field).controller!.text, '10');
  });

  testWidgets("the server's field error lands under the field", (tester) async {
    final repo = _FakeServiceProfile(
      saveError: ApiException(
        'Maximum travel distance cannot exceed 100 km',
        statusCode: 400,
        details: {
          '363': ['Maximum travel distance cannot exceed 100 km'],
        },
      ),
    );
    await _open(tester, repo);
    await tester.enterText(_field, '40'); // passes the app's check; the server says no
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Maximum travel distance cannot exceed 100 km'), findsOneWidget);
  });
}
