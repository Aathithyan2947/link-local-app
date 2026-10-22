import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/feed/data/feed_repository.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/feed/presentation/post_detail_screen.dart';
import 'package:link_local/features/feed/presentation/widgets/post_card.dart';
import 'package:link_local/features/members/data/members_repository.dart';
import 'package:link_local/features/messages/data/message_models.dart';
import 'package:link_local/features/messages/data/messages_repository.dart';
import 'package:link_local/features/messages/presentation/chat_screen.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

Conversation _chat(int id, String name) => Conversation.fromJson({
  'other': {
    'id': id,
    'profile': {'name': name},
  },
  'lastMessage': 'hi',
});

/// Chats on a fake server. [refuse] maps a user id to the 403 the server would give for them;
/// [broken] makes every send fail outright.
class _Messages implements MessagesRepository {
  final sent = <({int to, String content, String? entityType, int? entityId})>[];
  final refuse = <int, String>{};
  bool broken = false;
  List<Conversation> chats = [_chat(7, 'Priya'), _chat(8, 'Ravi'), _chat(9, 'Meena')];

  @override
  Future<List<Conversation>> conversations() async => chats;

  @override
  Future<void> send({
    required int receiverId,
    required String content,
    String? messageType,
    String? entityType,
    int? entityId,
  }) async {
    final req = RequestOptions(path: '/messages');
    if (broken) throw DioException(requestOptions: req, type: DioExceptionType.connectionError);
    final why = refuse[receiverId];
    if (why != null) {
      throw DioException(
        requestOptions: req,
        response: Response(requestOptions: req, statusCode: 403, data: {'success': false, 'message': why}),
        type: DioExceptionType.badResponse,
      );
    }
    sent.add((to: receiverId, content: content, entityType: entityType, entityId: entityId));
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// The neighbourhood directory on a fake server, searched by name like the real one.
class _Members implements MembersRepository {
  List<MemberItem> people = const [];

  /// When set, the directory answers only once this completes (a slow server).
  Completer<void>? slow;
  int calls = 0;

  @override
  Future<MembersPage> list({required String scope, int? areaId, String? q, int page = 1, int pageSize = 30}) async {
    calls++;
    await slow?.future;
    final query = (q ?? '').toLowerCase();
    final hits = people.where((m) => m.name.toLowerCase().contains(query)).toList();
    return MembersPage(items: hits, total: hits.length);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

MemberItem _person(int userId, String name) =>
    MemberItem(profileId: userId + 100, userId: userId, name: name, isServiceProvider: false, areaName: 'Pai Nagar');

class _Feed implements FeedRepository {
  final shares = <(int, String)>[];

  @override
  Future<void> sharePost(int id, {String channel = 'chat'}) async => shares.add((id, channel));

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

final _post = PostItem.fromJson({
  'id': 31,
  'postType': 'ask_help',
  'textContent': 'testing post 3',
  'user': {
    'id': 60,
    'profile': {'name': 'Aathi testing'},
  },
  '_count': {'shares': 0},
});

Future<(_Messages, _Feed)> _openCard(
  WidgetTester tester, {
  void Function(_Messages)? setUp,
  List<MemberItem> people = const [],
  _Members? members,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final messages = _Messages();
  setUp?.call(messages);
  final feed = _Feed();
  members ??= _Members()..people = people;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        messagesRepositoryProvider.overrideWithValue(messages),
        feedRepositoryProvider.overrideWithValue(feed),
        membersRepositoryProvider.overrideWithValue(members),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ListView(children: [PostCard(post: _post)])),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (messages, feed);
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.share_outlined));
  await tester.pumpAndSettle();
}

Finder get _send => find.byType(ElevatedButton);

void main() {
  testWidgets("Share opens 'Send to' with my chats, searchable; Send waits for a pick", (tester) async {
    await _openCard(tester);
    await _openSheet(tester);

    expect(find.text('Send to'), findsOneWidget);
    for (final n in ['Priya', 'Ravi', 'Meena']) {
      expect(find.text(n), findsOneWidget);
    }
    expect(tester.widget<ElevatedButton>(_send).onPressed, isNull, reason: 'nobody picked yet');

    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'pri');
    await tester.pumpAndSettle();
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Ravi'), findsNothing);
  });

  testWidgets('sending to two people: two chat messages pointing at the post, one share', (tester) async {
    final (messages, feed) = await _openCard(tester);
    await _openSheet(tester);
    await tester.tap(find.text('Priya'));
    await tester.tap(find.text('Ravi'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Add a message (optional)'), 'can you help?');
    await tester.tap(find.text('Send to 2'));
    await tester.pumpAndSettle();

    expect(messages.sent.map((m) => m.to), [7, 8]);
    expect(messages.sent.every((m) => m.entityType == 'post' && m.entityId == 31), isTrue);
    expect(messages.sent.first.content, 'can you help?');
    expect(feed.shares, [(31, 'chat')], reason: 'counted once');
    expect(find.text('Sent to 2 people'), findsOneWidget);
    expect(find.text('Send to'), findsNothing, reason: 'the sheet closes');
    expect(find.text('1'), findsOneWidget, reason: "the card's share count went up");
  });

  testWidgets("without a note it's sent as 'Shared a post'", (tester) async {
    final (messages, _) = await _openCard(tester);
    await _openSheet(tester);
    await tester.tap(find.text('Meena'));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(messages.sent.single.content, 'Shared a post');
    expect(find.text('Sent to Meena'), findsOneWidget);
  });

  testWidgets("one blocked recipient: the others still get it, and the reason is shown", (tester) async {
    final (messages, feed) = await _openCard(tester, setUp: (m) => m.refuse[8] = "You can't message this person.");
    await _openSheet(tester);
    await tester.tap(find.text('Priya'));
    await tester.tap(find.text('Ravi'));
    await tester.pump();
    await tester.tap(find.text('Send to 2'));
    await tester.pumpAndSettle();

    expect(messages.sent.map((m) => m.to), [7]);
    expect(feed.shares, hasLength(1));
    expect(find.text("Sent to Priya\nCouldn't send to Ravi: You can't message this person."), findsOneWidget);
  });

  testWidgets('if nothing goes out: "Could not share", nothing counted, the sheet stays', (tester) async {
    final (_, feed) = await _openCard(tester, setUp: (m) => m.broken = true);
    await _openSheet(tester);
    await tester.tap(find.text('Priya'));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(feed.shares, isEmpty);
    expect(find.text('Could not share'), findsOneWidget);
    expect(find.text('Send to'), findsOneWidget);
  });

  group('BUG-061: sharing with no chats yet', () {
    testWidgets('neighbours from the directory are listed and can be sent to', (tester) async {
      final (messages, feed) = await _openCard(
        tester,
        setUp: (m) => m.chats = [],
        people: [_person(21, 'Asha'), _person(22, 'Kiran')],
      );
      await _openSheet(tester);

      expect(find.text('People near you'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Kiran'), findsOneWidget);
      await tester.tap(find.text('Asha'));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(messages.sent.single.to, 21, reason: "addressed to the member's account id");
      expect(feed.shares, hasLength(1));
      expect(find.text('Sent to Asha'), findsOneWidget);
    });

    testWidgets('someone I already chat with is listed once, under Recent chats', (tester) async {
      await _openCard(tester, people: [_person(7, 'Priya'), _person(21, 'Asha')]);
      await _openSheet(tester);
      expect(find.text('Recent chats'), findsOneWidget);
      expect(find.text('People near you'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
    });

    testWidgets('searching finds directory members by name', (tester) async {
      await _openCard(tester, setUp: (m) => m.chats = [], people: [_person(21, 'Asha'), _person(22, 'Kiran')]);
      await _openSheet(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Search'), 'kir');
      await tester.pump(const Duration(milliseconds: 400)); // the search waits for typing to pause
      await tester.pumpAndSettle();
      expect(find.text('Kiran'), findsOneWidget);
      expect(find.text('Asha'), findsNothing);
    });

    testWidgets("while the directory loads, the chats show with a note that more are coming", (tester) async {
      final members = _Members()
        ..people = [_person(21, 'Asha')]
        ..slow = Completer<void>();
      await _openCard(tester, members: members);
      // Not pumpAndSettle: the "finding people" spinner keeps animating until the directory answers.
      await tester.tap(find.byIcon(Icons.share_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('Finding people near you…'), findsOneWidget,
          reason: 'two chats alone looked like the whole list');
      expect(find.text('Asha'), findsNothing);

      members.slow!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Finding people near you…'), findsNothing);
      expect(find.text('Asha'), findsOneWidget, reason: 'appears without having to tap anything');
    });

    testWidgets('the directory is fetched once per session, not on every open', (tester) async {
      final members = _Members()..people = [_person(21, 'Asha')];
      await _openCard(tester, members: members);
      await _openSheet(tester);
      expect(find.text('Asha'), findsOneWidget);
      Navigator.of(tester.element(find.text('Send to'))).pop();
      await tester.pumpAndSettle();

      await _openSheet(tester);
      expect(find.text('Asha'), findsOneWidget, reason: 'there straight away the second time');
      expect(members.calls, 1);
    });

    testWidgets('nobody at all says so instead of a blank sheet', (tester) async {
      await _openCard(tester, setUp: (m) => m.chats = []);
      await _openSheet(tester);
      expect(find.text('No one to share with yet.'), findsOneWidget);
    });
  });

  group('in the chat', () {
    Future<void> openChat(WidgetTester tester, Map<String, dynamic> message) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(Dio()),
            authControllerProvider.overrideWith(_SignedOut.new),
            threadProvider.overrideWith(
              (ref, id) async => ChatThread(otherId: id, otherName: 'Priya', messages: [ChatMessage.fromJson(message)]),
            ),
            conversationsProvider.overrideWith((ref) async => const []),
            unreadCountProvider.overrideWith((ref) async => 0),
            postDetailProvider.overrideWith((ref, id) => Completer<PostItem>().future),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const ChatScreen(otherUserId: 7, otherName: 'Priya')),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a shared post shows as a preview that opens the post', (tester) async {
      await openChat(tester, {
        'id': 1,
        'senderId': 7,
        'content': 'can you help?',
        'entityType': 'post',
        'entityId': 31,
        'post': {'id': 31, 'postType': 'ask_help', 'text': 'testing post 3', 'authorName': 'Aathi testing', 'isActive': true},
      });
      expect(find.text('can you help?'), findsOneWidget, reason: 'the note');
      expect(find.text('testing post 3'), findsOneWidget);
      expect(find.text('Aathi testing'), findsOneWidget);
      expect(find.text('Ask for help'), findsOneWidget);

      await tester.tap(find.text('View post'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<PostDetailScreen>(find.byType(PostDetailScreen)).id, 31);
    });

    testWidgets('a removed post says so', (tester) async {
      await openChat(tester, {
        'id': 1,
        'senderId': 7,
        'content': 'Shared a post',
        'entityType': 'post',
        'entityId': 31,
        'post': null,
      });
      expect(find.text('This post is no longer available'), findsOneWidget);
      expect(find.text('Shared a post'), findsNothing, reason: 'the placeholder text is not shown as a note');
    });
  });
}
