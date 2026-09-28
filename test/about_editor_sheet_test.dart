import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';
import 'package:link_local/features/profile/presentation/sections/about_editor_sheet.dart';

class _FakeProfileRepository implements ProfileRepository {
  Map<String, dynamic>? saved;

  @override
  Future<ProfileDetail> getMyProfile() async => ProfileDetail.fromJson({
        'id': 1,
        'name': 'Test',
        'aboutMe': 'Old about',
        'educations': [
          // A pending "Other" school: not in the catalog, so it must come back as typed text.
          {'id': 9, 'degree': 'B.Com', 'schoolName': 'Tiny Local School'},
        ],
        'professions': [
          {'id': 3, 'companyOrDetail': 'HCL', 'professionMaster': {'id': 1, 'category': 'Salaried'}},
        ],
      });

  @override
  Future<void> setAbout({
    required String aboutMe,
    required List<Map<String, dynamic>> educations,
    required List<Map<String, dynamic>> professions,
  }) async {
    saved = {'aboutMe': aboutMe, 'educations': educations, 'professions': professions};
  }

  @override
  Future<List<String>> educationDegrees() async => ['B.Com', 'Bachelors of Engineering'];
  @override
  Future<List<String>> schoolMasters() async => ['Campion School'];
  @override
  Future<List<String>> collegeMasters() async => ['Jai Hind College'];
  @override
  Future<List<IdName>> professions() async => const [IdName(1, 'Salaried'), IdName(2, 'Self-employed')];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<_FakeProfileRepository> _open(WidgetTester tester, {Future<void> Function()? afterSave}) async {
  // Phone-sized, so the whole sheet is laid out rather than lazily clipped.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _FakeProfileRepository();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileRepositoryProvider.overrideWithValue(repo),
      dioProvider.overrideWithValue(Dio()),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAboutEditor(context, afterSave: afterSave),
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
  testWidgets('loads existing values, including a not-yet-approved "Other"', (tester) async {
    await _open(tester);
    expect(find.text('Old about'), findsOneWidget);
    expect(find.text('B.Com'), findsOneWidget);
    expect(find.text('Tiny Local School'), findsOneWidget, reason: 'pending school shown as typed text');
    expect(find.text('Salaried'), findsOneWidget);
    expect(find.text('HCL'), findsOneWidget);
  });

  testWidgets('saves all three together and refreshes before closing', (tester) async {
    var refreshedBeforeClose = false;
    late _FakeProfileRepository repo;
    repo = await _open(tester, afterSave: () async {
      // The sheet must still be open while the screen underneath refetches.
      refreshedBeforeClose = find.text('Edit About').evaluate().isNotEmpty;
    });

    await tester.enterText(find.text('Old about'), 'New about');
    await tester.tap(find.text('Add education'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.saved!['aboutMe'], 'New about');
    expect(repo.saved!['educations'], [
      {'degree': 'B.Com', 'schoolName': 'Tiny Local School'},
    ], reason: 'the blank new row is dropped, the existing one kept as-is');
    expect(repo.saved!['professions'], [
      {'professionMasterId': 1, 'companyOrDetail': 'HCL'},
    ]);
    expect(refreshedBeforeClose, isTrue);
    expect(find.text('Edit About'), findsNothing, reason: 'sheet closes after saving');
  });

  testWidgets('closing with unsaved changes asks first', (tester) async {
    final repo = await _open(tester);
    await tester.enterText(find.text('Old about'), 'Edited');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Edit About'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Edit About'), findsNothing);
    expect(repo.saved, isNull, reason: 'discarding must not save');
  });

  testWidgets('the system back gesture also asks before discarding', (tester) async {
    await _open(tester);
    await tester.enterText(find.text('Old about'), 'Edited');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.text('Edit About'), findsOneWidget);
  });

  testWidgets('closing without changes just closes', (tester) async {
    await _open(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('Edit About'), findsNothing);
  });
}
