import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/discovery/data/group_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';

class _Admin extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 5, userType: 'resident', name: 'Asha', hasAddress: true),
      );
}

/// Group 3's members on a fake server; records how the admin left.
class _Server implements DiscoveryRepository {
  _Server(this.members);
  final List<GroupMember> members;
  final leaves = <int?>[];

  @override
  Future<List<GroupMember>> groupMembers(int id) async => members;
  @override
  Future<void> leaveGroup(int id, {int? newAdminUserId}) async => leaves.add(newAdminUserId);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

const _asha = GroupMember(userId: 5, name: 'Asha', isCreator: true);

Future<_Server> _openAsAdmin(WidgetTester tester, List<GroupMember> members) async {
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final server = _Server(members);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_Admin.new),
      discoveryRepositoryProvider.overrideWithValue(server),
      groupDetailProvider.overrideWith((ref, id) async => GroupDetail.fromJson({
            'id': 3,
            'title': 'Morning Runners',
            'creator': {
              'profile': {'name': 'Asha'},
            },
            '_count': {'members': members.length},
            'isCreator': true,
            'myMembership': {'status': 'joined'},
          })),
      homeFeedProvider.overrideWith((ref) => Completer<HomeFeed>().future),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupProfileScreen(id: 3))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return server;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('BUG-081: the group admin can exit', () {
    testWidgets('by handing the group to a member they pick', (tester) async {
      final server = await _openAsAdmin(tester, const [
        _asha,
        GroupMember(userId: 8, name: 'Ravi'),
        GroupMember(userId: 9, name: 'Meera'),
      ]);
      await _tap(tester, 'Exit Group');

      expect(find.text('Choose a new admin'), findsOneWidget);
      final sheet = find.ancestor(of: find.text('Choose a new admin'), matching: find.byType(Column)).first;
      expect(find.descendant(of: sheet, matching: find.text('Asha')), findsNothing, reason: 'not themselves');
      await _tap(tester, 'Ravi');

      expect(find.text('Make Ravi the admin?'), findsOneWidget);
      await _tap(tester, 'Exit group');
      expect(server.leaves, [8]);
      expect(find.byType(GroupProfileScreen), findsNothing, reason: 'they are no longer in the group');
      expect(find.text('Ravi is now the admin. You have left the group.'), findsOneWidget);
    });

    testWidgets('closing the group when they are its only member', (tester) async {
      final server = await _openAsAdmin(tester, const [_asha]);
      await _tap(tester, 'Exit Group');

      expect(find.text('Close this group?'), findsOneWidget);
      await _tap(tester, 'Exit and close');
      expect(server.leaves, [null]);
      expect(find.text('Group closed'), findsOneWidget);
    });

    testWidgets('backing out of the member list changes nothing', (tester) async {
      final server = await _openAsAdmin(tester, const [_asha, GroupMember(userId: 8, name: 'Ravi')]);
      await _tap(tester, 'Exit Group');
      await tester.tapAt(const Offset(20, 20)); // outside the sheet
      await tester.pumpAndSettle();
      expect(server.leaves, isEmpty);
      expect(find.byType(GroupProfileScreen), findsOneWidget);
    });
  });
}
