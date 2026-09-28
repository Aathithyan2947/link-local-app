import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';
import 'package:link_local/features/profile/presentation/sections/contact_field_sheet.dart';

class _FakeProfileRepository implements ProfileRepository {
  Map<String, dynamic>? patched;

  @override
  Future<void> updateBasic(Map<String, dynamic> data) async => patched = data;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<_FakeProfileRepository> _open(WidgetTester tester, ContactField field, String current) async {
  final repo = _FakeProfileRepository();
  await tester.pumpWidget(ProviderScope(
    overrides: [profileRepositoryProvider.overrideWithValue(repo), dioProvider.overrideWithValue(Dio())],
    child: MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showContactFieldEditor(context, field: field, current: current, signInValue: '9092193031'),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  test('validation', () {
    expect(validateContactField(ContactField.phone, '9876543210'), isNull);
    expect(validateContactField(ContactField.phone, '98765'), isNotNull);
    expect(validateContactField(ContactField.email, 'a@b.co'), isNull);
    expect(validateContactField(ContactField.email, 'a@b'), isNotNull);
    expect(validateContactField(ContactField.phone, ''), isNull, reason: 'empty clears the field');
  });

  testWidgets('saves the public phone, never the sign-in one', (tester) async {
    final repo = await _open(tester, ContactField.phone, '');
    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.patched, {'servicePhone': '9876543210'});
    expect(find.text('Edit mobile number'), findsNothing);
  });

  testWidgets('an invalid email is rejected without saving', (tester) async {
    final repo = await _open(tester, ContactField.email, '');
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(repo.patched, isNull);
  });

  testWidgets('clearing sends an empty value, falling back to the sign-in number', (tester) async {
    final repo = await _open(tester, ContactField.phone, '9876543210');
    expect(find.textContaining('9092193031'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.patched, {'servicePhone': ''});
  });
}
