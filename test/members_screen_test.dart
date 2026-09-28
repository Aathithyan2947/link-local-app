import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/members/data/members_repository.dart';
import 'package:link_local/features/members/presentation/members_screen.dart';

class _FakeMembersRepo implements MembersRepository {
  final calls = <String>[];

  @override
  Future<MembersPage> list({required String scope, int? areaId, String? q, int page = 1, int pageSize = 30}) async {
    calls.add('$scope|${q ?? ''}|$page');
    const all = [
      MemberItem(profileId: 1, name: 'Asha', isServiceProvider: true, roleLabel: 'Tutor', areaName: 'Pai Nagar'),
      MemberItem(profileId: 2, name: 'Bala', isServiceProvider: false, areaName: 'Gaimukh'),
    ];
    final hits = all.where((m) => (q ?? '').isEmpty || m.name.toLowerCase().contains(q!.toLowerCase())).toList();
    return MembersPage(items: hits, total: hits.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<_FakeMembersRepo> _pump(WidgetTester tester, {String scope = 'city'}) async {
  final repo = _FakeMembersRepo();
  await tester.pumpWidget(ProviderScope(
    overrides: [membersRepositoryProvider.overrideWithValue(repo), dioProvider.overrideWithValue(Dio())],
    child: MaterialApp(home: MembersScreen(initialScope: scope)),
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

  testWidgets('lists members in the scope Home was showing, with the total', (tester) async {
    final repo = await _pump(tester, scope: 'area');
    expect(repo.calls.first, startsWith('area|'));
    expect(find.text('Members (2)'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Tutor · Pai Nagar'), findsOneWidget);
    expect(find.text('Provider'), findsOneWidget, reason: 'providers are marked');
  });

  testWidgets('search narrows the list', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'bal');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Bala'), findsOneWidget);
    expect(find.text('Asha'), findsNothing);
  });

  testWidgets('changing scope reloads from page 1', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Lane'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'lane||1');
  });
}
