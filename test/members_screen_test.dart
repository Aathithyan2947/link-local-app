import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/members/data/members_repository.dart';
import 'package:link_local/features/members/presentation/members_screen.dart';

class _FakeMembersRepo implements MembersRepository {
  final calls = <String>[];

  @override
  Future<MembersPage> list({required String scope, int? areaId, String? q, int page = 1, int pageSize = 30}) async {
    calls.add('$scope|${q ?? ''}|$page');
    final all = [
      MemberItem(
        profileId: 1,
        name: 'Asha',
        isServiceProvider: true,
        roleLabel: 'Tutor',
        areaName: 'Pai Nagar',
        joinedAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
      MemberItem(
        profileId: 2,
        name: 'Bala',
        isServiceProvider: false,
        areaName: 'Gaimukh',
        joinedAt: DateTime.now().subtract(const Duration(days: 90)),
      ),
    ];
    final hits = all.where((m) => (q ?? '').isEmpty || m.name.toLowerCase().contains(q!.toLowerCase())).toList();
    return MembersPage(items: hits, total: hits.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<_FakeMembersRepo> _pump(WidgetTester tester, {String scope = 'city'}) async {
  tester.view.physicalSize = const Size(1800, 3000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _FakeMembersRepo();
  await tester.pumpWidget(ProviderScope(
    overrides: [membersRepositoryProvider.overrideWithValue(repo), dioProvider.overrideWithValue(Dio())],
    child: MaterialApp(theme: AppTheme.light, home: MembersScreen(initialScope: scope)),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  test('subtitle joins role and area, skipping gaps', () {
    expect(const MemberItem(profileId: 1, name: 'A', isServiceProvider: true, roleLabel: 'Tutor', areaName: 'X').subtitle,
        'Tutor · X');
    expect(const MemberItem(profileId: 1, name: 'A', isServiceProvider: false, areaName: 'X').subtitle, 'X');
    expect(const MemberItem(profileId: 1, name: 'A', isServiceProvider: false).subtitle, '');
  });

  test('joinedAt is read from the server; "new" means the last 30 days', () {
    final m = MemberItem.fromJson({'profileId': 1, 'name': 'A', 'joinedAt': '2026-11-10T10:00:00.000Z'});
    expect(m.joinedAt, isNotNull);
    expect(MemberItem.fromJson({'profileId': 1, 'name': 'A'}).joinedAt, isNull, reason: 'older servers');
    expect(MemberItem(profileId: 1, name: 'A', isServiceProvider: false, joinedAt: DateTime.now()).isNew, isTrue);
    expect(
      MemberItem(
        profileId: 1,
        name: 'A',
        isServiceProvider: false,
        joinedAt: DateTime.now().subtract(const Duration(days: 31)),
      ).isNew,
      isFalse,
    );
    expect(const MemberItem(profileId: 1, name: 'A', isServiceProvider: false).isNew, isFalse);
  });

  group('BUG-079: the All Members page follows the Figma', () {
    testWidgets('green header, then "Members in <scope> (total)", then role and area per member', (tester) async {
      final repo = await _pump(tester, scope: 'area');
      expect(repo.calls.first, startsWith('area|'));
      expect(find.text('All members nearby'), findsOneWidget);
      expect(find.text('Members in Area (2)', findRichText: true), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Tutor'), findsOneWidget);
      expect(find.text('Pai Nagar'), findsOneWidget);
    });

    testWidgets('members who joined recently get the Welcome sticker', (tester) async {
      await _pump(tester);
      final asha = find.ancestor(of: find.text('Asha'), matching: find.byKey(const ValueKey('member-1')));
      final bala = find.ancestor(of: find.text('Bala'), matching: find.byKey(const ValueKey('member-2')));
      expect(find.descendant(of: asha, matching: find.textContaining('Welcome')), findsOneWidget);
      expect(find.descendant(of: bala, matching: find.textContaining('Welcome')), findsNothing);
    });

    testWidgets('search narrows the list', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'bal');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Bala'), findsOneWidget);
      expect(find.text('Asha'), findsNothing);
    });

    testWidgets('the dropdown changes the scope and reloads from page 1', (tester) async {
      final repo = await _pump(tester);
      await tester.tap(find.text('Members in City (2)', findRichText: true));
      await tester.pumpAndSettle();
      for (final label in ['My Society', 'Lane', 'Area', 'City']) {
        expect(find.text(label), findsOneWidget, reason: '$label is offered');
      }
      await tester.tap(find.text('Lane'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'lane||1');
      expect(find.text('Members in Lane (2)', findRichText: true), findsOneWidget);
    });

    testWidgets('fits a phone-width screen with a long name, role and the sticker', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [membersRepositoryProvider.overrideWithValue(_LongNames()), dioProvider.overrideWithValue(Dio())],
        child: MaterialApp(theme: AppTheme.light, home: const MembersScreen()),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Welcome'), findsOneWidget);
    });
  });
}

class _LongNames implements MembersRepository {
  @override
  Future<MembersPage> list({required String scope, int? areaId, String? q, int page = 1, int pageSize = 30}) async =>
      MembersPage(items: [
        MemberItem(
          profileId: 1,
          name: 'Venkataraghavan Subramaniam Iyer',
          isServiceProvider: true,
          roleLabel: 'Classical Carnatic Music and Veena Teacher',
          areaName: 'Kasarvadavali, Ghodbunder Road',
          joinedAt: DateTime.now(),
        ),
      ], total: 1);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
