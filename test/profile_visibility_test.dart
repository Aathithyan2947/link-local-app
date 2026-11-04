import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/discovery/presentation/user_profile_screen.dart';
import 'package:link_local/features/feed/data/feed_repository.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/feed/presentation/user_posts_screen.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';
import 'package:link_local/features/orders/data/orders_repository.dart';

class _Asha extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 5, userType: 'resident', name: 'Asha', hasAddress: true),
      );
}

/// What the server answers when the owner's Profile visibility leaves this viewer out.
DioException _status(int code, String message) {
  final req = RequestOptions(path: '/posts');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: code, data: {'success': false, 'message': message}),
    type: DioExceptionType.badResponse,
  );
}

/// Ravi's posts; [reject] is what the server answers instead.
class _Feed implements FeedRepository {
  Object? reject;
  int fetches = 0;

  @override
  Future<List<PostItem>> postsBy(int userId) async {
    fetches++;
    if (reject != null) throw reject!;
    return [
      PostItem.fromJson({
        'id': 1,
        'postType': 'ask_help',
        'textContent': 'anyone up for a run?',
        'createdAt': '2026-10-09T10:00:00.000Z',
        'user': {
          'id': 50,
          'profile': {'name': 'Ravi'},
        },
      }),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// Ravi's member (#8) and provider (#5) profiles, and group 3's members, on a fake server.
/// [hidden] is Ravi switching his Profile visibility to "Only me".
class _Server implements DiscoveryRepository {
  bool hidden = false;
  int profileFetches = 0;
  GroupMembers members = const GroupMembers([]);
  final leaves = <int?>[];

  Future<T> _profile<T>(T profile) async {
    profileFetches++;
    if (hidden) throw _status(403, 'This profile is private');
    return profile;
  }

  @override
  Future<PublicProfile> publicProfile(int id) => _profile(PublicProfile.fromJson({
        'id': 8,
        'name': 'Ravi',
        'user': {'id': 50, 'userType': 'resident'},
      }));

  @override
  Future<ServiceProviderDetail> serviceProvider(int id) => _profile(ServiceProviderDetail.fromJson({
        'id': 5,
        'name': 'Ravi Bakes',
        'user': {'id': 50},
      }));

  @override
  Future<GroupMembers> groupMembers(int id) async => members;
  @override
  Future<void> leaveGroup(int id, {int? newAdminUserId}) async => leaves.add(newAdminUserId);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// A launcher page with an "open" button that pushes [page], like tapping a card. [appRetry]
/// keeps Riverpod's default automatic retry, as the app's own ProviderScope does.
Future<void> _pump(
  WidgetTester tester, {
  required Widget page,
  _Server? server,
  _Feed? feed,
  bool creator = false,
  bool appRetry = false,
}) async {
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    // No automatic retries, so a fetch count is the number of times the page asked.
    retry: appRetry ? null : (_, _) => null,
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_Asha.new),
      discoveryRepositoryProvider.overrideWithValue(server ?? _Server()),
      feedRepositoryProvider.overrideWithValue(feed ?? _Feed()),
      myOrdersProvider.overrideWith((ref) async => const []),
      homeFeedProvider.overrideWith((ref) => Completer<HomeFeed>().future),
      groupDetailProvider.overrideWith((ref, id) async => GroupDetail.fromJson({
            'id': 3,
            'title': 'Morning Runners',
            'creator': {
              'profile': {'name': 'Asha'},
            },
            '_count': {'members': 4},
            'isCreator': creator,
            'myMembership': {'status': 'joined'},
          })),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      navigatorObservers: [appRouteObserver],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await _open(tester);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester, Type page) async {
  Navigator.of(tester.element(find.byType(page))).pop();
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group("BUG-104: a hidden profile's View More posts", () {
    testWidgets('say "This profile is private", like the profile, with no Retry', (tester) async {
      final feed = _Feed()..reject = _status(403, 'This profile is private');
      await _pump(tester, page: const UserPostsScreen(userId: 50, name: 'Ravi'), feed: feed);

      expect(find.text('This profile is private'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.text('anyone up for a run?'), findsNothing);
      expect(find.text('Retry'), findsNothing, reason: "retrying won't change their setting");
      expect(find.byType(BackButton), findsOneWidget, reason: 'the app bar keeps its back button');
      expect(find.byIcon(Icons.chevron_left), findsNothing, reason: 'and the page adds no second one');
    });

    testWidgets("show it at once: a 403 isn't retried, as the app would by default", (tester) async {
      final feed = _Feed()..reject = _status(403, 'This profile is private');
      await _pump(tester, page: const UserPostsScreen(userId: 50, name: 'Ravi'), feed: feed, appRetry: true);
      expect(find.text('This profile is private'), findsOneWidget);
      expect(feed.fetches, 1, reason: 'each retry kept a spinner up, ~40s in all');
    });

    testWidgets('a real failure still offers Retry', (tester) async {
      final feed = _Feed()..reject = _status(500, 'Internal server error');
      await _pump(tester, page: const UserPostsScreen(userId: 50, name: 'Ravi'), feed: feed);
      expect(find.text('This profile is private'), findsNothing);
      expect(find.text("Couldn't load the posts"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a visible profile still lists the posts', (tester) async {
      await _pump(tester, page: const UserPostsScreen(userId: 50, name: 'Ravi'));
      expect(find.text('anyone up for a run?'), findsOneWidget);
      expect(find.text('This profile is private'), findsNothing);
    });
  });

  group('BUG-104: group Members with private profiles', () {
    const asha = GroupMember(userId: 5, name: 'Asha', isCreator: true);
    const meera = GroupMember(userId: 9, name: 'Meera');

    testWidgets('are counted, not listed: a muted line says how many', (tester) async {
      final server = _Server()..members = const GroupMembers([asha, meera], hiddenCount: 2);
      await _pump(tester, page: const GroupProfileScreen(id: 3), server: server);
      await _tap(tester, '4 Members');

      expect(find.text('Members (4)'), findsOneWidget, reason: 'the count still includes everyone who joined');
      expect(find.text('Meera'), findsOneWidget);
      expect(find.text('2 members have private profiles'), findsOneWidget);
    });

    testWidgets('one hidden member reads in the singular', (tester) async {
      final server = _Server()..members = const GroupMembers([asha, meera], hiddenCount: 1);
      await _pump(tester, page: const GroupProfileScreen(id: 3), server: server);
      await _tap(tester, '4 Members');
      expect(find.text('Members (3)'), findsOneWidget);
      expect(find.text('1 member has a private profile'), findsOneWidget);
    });

    testWidgets('nobody hidden: no line', (tester) async {
      final server = _Server()..members = const GroupMembers([asha, meera]);
      await _pump(tester, page: const GroupProfileScreen(id: 3), server: server);
      await _tap(tester, '4 Members');
      expect(find.text('Members (2)'), findsOneWidget);
      expect(find.textContaining('private profile'), findsNothing);
    });

    testWidgets("the admin isn't told they're the only member when the others are hidden", (tester) async {
      final server = _Server()..members = const GroupMembers([asha], hiddenCount: 2);
      await _pump(tester, page: const GroupProfileScreen(id: 3), server: server, creator: true);
      await _tap(tester, 'Exit Group');

      expect(find.text('Close this group?'), findsNothing);
      expect(find.text('No member to hand over to'), findsOneWidget);
      await _tap(tester, 'OK');
      expect(server.leaves, isEmpty, reason: 'nothing was sent');
      expect(find.byType(GroupProfileScreen), findsOneWidget);
    });

    test('the repository reads hiddenCount beside the list, and 0 from a server without it', () async {
      Future<GroupMembers> read(Map<String, dynamic> body) {
        final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = _Adapter(body);
        return DiscoveryRepository(dio).groupMembers(3);
      }

      final row = {'userId': 9, 'name': 'Meera', 'photoUrl': null, 'isCreator': false};
      final now = await read({
        'success': true,
        'data': [row],
        'meta': {'hiddenCount': 2},
      });
      expect(now.members.single.name, 'Meera');
      expect(now.hiddenCount, 2);

      final before = await read({
        'success': true,
        'data': [row],
      });
      expect(before.members, hasLength(1));
      expect(before.hiddenCount, 0);
    });
  });

  group('BUG-104: a profile is fetched again each time it is opened', () {
    testWidgets('member profile: hidden since it was last opened → private on reopen', (tester) async {
      final server = _Server();
      await _pump(tester, page: const UserProfileScreen(id: 8), server: server);
      expect(find.text('Ravi'), findsWidgets);
      expect(server.profileFetches, 1);

      server.hidden = true; // Ravi switches to "Only me"
      await _back(tester, UserProfileScreen);
      await _open(tester);

      expect(server.profileFetches, 2, reason: 'not the copy from the first visit');
      expect(find.text('This profile is private'), findsOneWidget);
    });

    testWidgets('provider profile: the same', (tester) async {
      final server = _Server();
      await _pump(tester, page: const ServiceProviderDetailScreen(id: 5), server: server);
      expect(find.text('Ravi Bakes'), findsWidgets);
      expect(server.profileFetches, 1);

      server.hidden = true;
      await _back(tester, ServiceProviderDetailScreen);
      await _open(tester);

      expect(server.profileFetches, 2);
      expect(find.text('This profile is private'), findsOneWidget);
    });

    for (final (label, page) in [
      ('member', const UserProfileScreen(id: 8) as Widget),
      ('provider', const ServiceProviderDetailScreen(id: 5) as Widget),
    ]) {
      testWidgets("$label profile: a 403 isn't retried, as the app would by default", (tester) async {
        final server = _Server()..hidden = true;
        await _pump(tester, page: page, server: server, appRetry: true);
        expect(find.text('This profile is private'), findsOneWidget);
        expect(server.profileFetches, 1);
      });
    }

    testWidgets('made visible again → shows on reopen', (tester) async {
      final server = _Server()..hidden = true;
      await _pump(tester, page: const UserProfileScreen(id: 8), server: server);
      expect(find.text('This profile is private'), findsOneWidget);

      server.hidden = false;
      await _back(tester, UserProfileScreen);
      await _open(tester);
      expect(find.text('This profile is private'), findsNothing);
      expect(find.text('Ravi'), findsWidgets);
    });

    testWidgets('pull-to-refresh still refetches an open profile', (tester) async {
      final server = _Server();
      await _pump(tester, page: const UserProfileScreen(id: 8), server: server);
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(server.profileFetches, 2);
      expect(find.text('Ravi'), findsWidgets);
    });
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);
  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}
