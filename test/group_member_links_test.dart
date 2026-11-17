import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/router/app_router.dart' show appRouteObserver;
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/discovery/data/group_detail_models.dart';
import 'package:link_local/features/discovery/data/public_profile_models.dart';
import 'package:link_local/features/discovery/data/sp_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/group_members_screen.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/discovery/presentation/user_profile_screen.dart';
import 'package:link_local/features/feed/data/feed_repository.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';
import 'package:link_local/features/messages/data/message_models.dart';
import 'package:link_local/features/messages/data/messages_repository.dart' show threadProvider;
import 'package:link_local/features/messages/presentation/chat_screen.dart';
import 'package:link_local/features/orders/data/orders_repository.dart';

/// Asha (user #5, profile #2) is signed in.
class _Asha extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 5, userType: 'resident', name: 'Asha', hasAddress: true),
      );
}

/// Group 3's members, and the profiles their names open.
class _Server implements DiscoveryRepository {
  _Server(this.members);
  final GroupMembers members;
  final opened = <String>[];

  @override
  Future<GroupMembers> groupMembers(int id) async => members;

  @override
  Future<PublicProfile> publicProfile(int id) async {
    opened.add('member #$id');
    return PublicProfile.fromJson({
      'id': id,
      'name': 'Meera',
      'user': {'id': 9, 'userType': 'resident'},
    });
  }

  @override
  Future<ServiceProviderDetail> serviceProvider(int id) async {
    opened.add('provider #$id');
    return ServiceProviderDetail.fromJson({
      'id': id,
      'name': id == 2 ? 'Asha' : 'Ravi Bakes',
      'user': {'id': id == 2 ? 5 : 50},
    });
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Feed implements FeedRepository {
  @override
  Future<List<PostItem>> postsBy(int userId) async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

const _asha = GroupMember(userId: 5, name: 'Asha', isCreator: true, isAdmin: true, profileId: 2);
const _meera = GroupMember(userId: 9, name: 'Meera', profileId: 8);
const _ravi = GroupMember(userId: 50, name: 'Ravi Bakes', profileId: 5, isServiceProvider: true);

/// Group 3's page, pushed from a launcher, with its Group Members page open.
Future<void> _openMembers(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_Asha.new),
      discoveryRepositoryProvider.overrideWithValue(server),
      feedRepositoryProvider.overrideWithValue(_Feed()),
      myOrdersProvider.overrideWith((ref) async => const []),
      homeFeedProvider.overrideWith((ref) => Completer<HomeFeed>().future),
      threadProvider.overrideWith((ref, otherId) async => ChatThread(otherId: otherId, otherName: 'Meera', messages: const [])),
      groupDetailProvider.overrideWith((ref, id) async => GroupDetail.fromJson({
            'id': 3,
            'title': 'Morning Runners',
            'creator': {
              'profile': {'name': 'Asha'},
            },
            '_count': {'members': 3},
            'myMembership': {'status': 'joined'},
          })),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      navigatorObservers: [appRouteObserver],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupProfileScreen(id: 3))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('3 Members'));
  await tester.pumpAndSettle();
}

Future<void> _tapName(WidgetTester tester, String name) async {
  await tester.tap(find.descendant(of: find.byType(GroupMembersScreen), matching: find.text(name)));
  await tester.pumpAndSettle();
}

void main() {
  group('Group Members: a name opens that member', () {
    testWidgets("a resident's name opens their member profile, and back returns to the list", (tester) async {
      final server = _Server(const GroupMembers([_asha, _meera, _ravi]));
      await _openMembers(tester, server);

      await _tapName(tester, 'Meera');
      expect(tester.widget<UserProfileScreen>(find.byType(UserProfileScreen)).id, 8);
      expect(server.opened, ['member #8']);

      Navigator.of(tester.element(find.byType(UserProfileScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(GroupMembersScreen), findsOneWidget, reason: 'the members page is still underneath');
      expect(find.text('Total Members 3'), findsOneWidget);
    });

    testWidgets("a provider's name opens their provider page", (tester) async {
      final server = _Server(const GroupMembers([_asha, _meera, _ravi]));
      await _openMembers(tester, server);
      await _tapName(tester, 'Ravi Bakes');
      expect(tester.widget<ServiceProviderDetailScreen>(find.byType(ServiceProviderDetailScreen)).id, 5);
      expect(find.byType(UserProfileScreen), findsNothing);
    });

    testWidgets('your own name opens My Profile', (tester) async {
      final server = _Server(const GroupMembers([_asha, _meera, _ravi]));
      await _openMembers(tester, server);
      await _tapName(tester, 'Asha');
      expect(tester.widget<ServiceProviderDetailScreen>(find.byType(ServiceProviderDetailScreen)).id, 2,
          reason: 'the owner view of their own profile, as Profile → My Profile opens it');
      expect(find.byType(UserProfileScreen), findsNothing);
    });

    testWidgets("an older server without profile ids leaves the names as plain text", (tester) async {
      final server = _Server(const GroupMembers([GroupMember(userId: 9, name: 'Meera')]));
      await _openMembers(tester, server);
      await _tapName(tester, 'Meera');
      expect(find.byType(UserProfileScreen), findsNothing);
      expect(server.opened, isEmpty);
    });

    test('the profile id and provider flag are read from the members list', () {
      final m = GroupMember.fromJson(
          {'userId': 50, 'name': 'Ravi', 'profileId': 5, 'isServiceProvider': true, 'isCreator': false});
      expect(m.profileId, 5);
      expect(m.isServiceProvider, isTrue);
      final old = GroupMember.fromJson({'userId': 9, 'name': 'Meera'});
      expect(old.profileId, isNull);
      expect(old.isServiceProvider, isFalse);
    });
  });

  group('BUG-082: Members opens the Group Members page from the Figma', () {
    testWidgets('a full page (not a sheet) with Admin and Members sections and the total', (tester) async {
      final server = _Server(const GroupMembers([
        _asha,
        GroupMember(userId: 9, name: 'Meera', profileId: 8, isAdmin: true),
        _ravi,
      ]));
      await _openMembers(tester, server);
      expect(find.byType(GroupMembersScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Group Members'), findsOneWidget);
      expect(find.text('Total Members 3'), findsOneWidget);
      expect(find.text('Admin (2)'), findsOneWidget);
      expect(find.text('Members (1)'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Meera')).dy,
        lessThan(tester.getTopLeft(find.text('Members (1)')).dy),
        reason: 'a co-admin is listed under Admin',
      );
    });

    testWidgets('your own row says You; the others have a message button that opens the chat', (tester) async {
      final server = _Server(const GroupMembers([_asha, _meera, _ravi]));
      await _openMembers(tester, server);
      final ashaRow = find.byKey(const ValueKey('group-member-5'));
      expect(find.descendant(of: ashaRow, matching: find.text('You')), findsOneWidget);
      expect(find.descendant(of: ashaRow, matching: find.byIcon(Icons.message_rounded)), findsNothing);
      expect(find.byTooltip('Message Ravi Bakes'), findsOneWidget);

      await tester.tap(find.byTooltip('Message Meera'));
      await tester.pumpAndSettle();
      expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).otherUserId, 9);
    });

    testWidgets('each row shows the month they joined', (tester) async {
      final server = _Server(GroupMembers([
        GroupMember(userId: 9, name: 'Meera', profileId: 8, joinedAt: DateTime(2026, 5, 4)),
      ]));
      await _openMembers(tester, server);
      expect(find.text('Joined May, 2026'), findsOneWidget);
    });

    testWidgets('search narrows the list by name', (tester) async {
      final server = _Server(const GroupMembers([_asha, _meera, _ravi]));
      await _openMembers(tester, server);
      await tester.enterText(find.byType(TextField), 'rav');
      await tester.pumpAndSettle();
      expect(find.text('Ravi Bakes'), findsOneWidget);
      expect(find.text('Meera'), findsNothing);
    });

    testWidgets('members with private profiles are counted, not listed', (tester) async {
      final server = _Server(const GroupMembers([_asha], hiddenCount: 2));
      await _openMembers(tester, server);
      expect(find.text('Total Members 3'), findsOneWidget);
      expect(find.text('2 members have private profiles'), findsOneWidget);
    });

    testWidgets('fits a phone-width screen with long names', (tester) async {
      final server = _Server(GroupMembers([
        const GroupMember(userId: 5, name: 'Asha Venkataraghavan Subramaniam', isCreator: true, profileId: 2),
        GroupMember(
          userId: 9,
          name: 'Meenakshisundaram Ramachandran Iyer',
          profileId: 8,
          joinedAt: DateTime(2026, 9, 14),
        ),
      ]));
      await _openMembers(tester, server);
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Joined Sep, 2026'), findsOneWidget);
    });

    test('isAdmin and joinedAt are read from the members list (creator counts as admin on older servers)', () {
      final m = GroupMember.fromJson(
          {'userId': 9, 'name': 'Meera', 'isAdmin': true, 'joinedAt': '2026-05-04T10:00:00.000Z'});
      expect(m.isAdmin, isTrue);
      expect(m.joinedAt, isNotNull);
      final old = GroupMember.fromJson({'userId': 5, 'name': 'Asha', 'isCreator': true});
      expect(old.isAdmin, isTrue);
      expect(old.joinedAt, isNull);
    });
  });
}
