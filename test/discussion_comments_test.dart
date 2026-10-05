import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/feed/data/feed_repository.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/feed/presentation/widgets/comments_panel.dart';
import 'package:link_local/features/feed/presentation/widgets/discussion_card.dart';
import 'package:link_local/features/feed/presentation/widgets/like_sync.dart';
import 'package:link_local/features/home/data/home_models.dart';

/// In-memory stand-in for the posts API: one post with one comment thread.
class _FakeFeed implements FeedRepository {
  final postLikeCalls = <bool>[];
  final commentLikeCalls = <(int, bool)>[];
  final added = <(String, int?)>[];
  bool postLiked = false;
  int postLikes = 0;
  bool canInteract = true;
  int nextId = 100;
  final commentList = <PostComment>[
    PostComment(id: 1, comment: 'this is great', authorName: 'Aathi', createdAt: DateTime.now(), replyCount: 1),
  ];
  final replyList = <PostComment>[
    PostComment(id: 2, comment: 'agreed', authorName: 'Simran', createdAt: DateTime.now(), parentId: 1),
  ];

  @override
  Future<({bool liked, int likes})> setLike(int id, bool liked) async {
    postLikeCalls.add(liked);
    if (liked != postLiked) postLikes += liked ? 1 : -1;
    postLiked = liked;
    return (liked: postLiked, likes: postLikes);
  }

  @override
  Future<({bool liked, int likes})> setCommentLike(int commentId, bool liked) async {
    commentLikeCalls.add((commentId, liked));
    return (liked: liked, likes: liked ? 1 : 0);
  }

  @override
  Future<CommentPage> comments(int postId, {String sort = 'top', int page = 1, int pageSize = 20}) async =>
      CommentPage(items: List.of(commentList), hasMore: false, totalComments: 2, canInteract: canInteract);

  @override
  Future<List<PostComment>> replies(int commentId) async => List.of(replyList);

  @override
  Future<PostComment> addComment(int id, String comment, {int? parentCommentId}) async {
    added.add((comment, parentCommentId));
    return PostComment(
      id: nextId++,
      comment: comment,
      authorName: 'Me',
      createdAt: DateTime.now(),
      parentId: parentCommentId == null ? null : 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

DiscussionItem _item({bool canInteract = true}) => DiscussionItem(
  id: 11,
  text: 'Testing this group',
  authorName: 'simran 1',
  likes: 0,
  comments: 2,
  createdAt: DateTime.now(),
  canInteract: canInteract,
  groupId: 10,
  groupTitle: 'test group',
  topComment: PostComment(id: 1, comment: 'this is great', authorName: 'Aathi', createdAt: DateTime.now()),
);

Future<void> _pumpCard(WidgetTester tester, _FakeFeed feed, DiscussionItem item, {VoidCallback? onJoin}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [feedRepositoryProvider.overrideWithValue(feed), dioProvider.overrideWithValue(Dio())],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [DiscussionCard(item: item, onJoin: onJoin)],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('LikeSync', () {
    test('a burst of taps sends one request and ends in the final state', () async {
      final sent = <bool>[];
      final pending = Completer<({bool liked, int likes})>();
      final sync = LikeSync(
        liked: false,
        likes: 0,
        send: (liked) {
          sent.add(liked);
          return pending.future;
        },
        onChanged: () {},
      );
      for (var i = 0; i < 5; i++) {
        sync.tap(); // true, false, true, false, true
      }
      expect(sync.liked, isTrue, reason: 'the heart follows taps immediately');
      pending.complete((liked: true, likes: 1));
      await Future<void>.delayed(Duration.zero);
      expect(sent, [true], reason: 'taps during the request only move the wanted state');
      expect(sync.likes, 1);
    });

    test('ending on the opposite state sends one follow-up', () async {
      final sent = <bool>[];
      var serverLiked = false;
      final first = Completer<void>();
      final sync = LikeSync(
        liked: false,
        likes: 0,
        send: (liked) async {
          sent.add(liked);
          if (sent.length == 1) await first.future;
          serverLiked = liked;
          return (liked: liked, likes: liked ? 1 : 0);
        },
        onChanged: () {},
      );
      sync.tap();
      sync.tap(); // back to not liked while the like is in flight
      first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sent, [true, false]);
      expect(serverLiked, isFalse);
      expect(sync.liked, isFalse);
      expect(sync.likes, 0);
    });

    test('a refusal puts the heart back', () async {
      Object? error;
      final sync = LikeSync(
        liked: false,
        likes: 3,
        send: (_) async => throw Exception('403'),
        onChanged: () {},
        onError: (e) => error = e,
      );
      sync.tap();
      expect(sync.liked, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(sync.liked, isFalse);
      expect(sync.likes, 3);
      expect(error, isNotNull);
    });
  });

  testWidgets('the card heart likes at once, and rapid taps settle to one state', (tester) async {
    final feed = _FakeFeed();
    await _pumpCard(tester, feed, _item());

    await tester.tap(find.bySemanticsLabel('Like'));
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget, reason: 'filled straight away');

    // Two more quick taps while the first request may still be settling.
    await tester.tap(find.bySemanticsLabel('Unlike'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Like'));
    await tester.pumpAndSettle();
    expect(feed.postLiked, isTrue);
    expect(feed.postLikes, 1, reason: 'never more than one like, however many taps');
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('comments open in a sheet: like, reply into the thread, and the card count updates', (tester) async {
    final feed = _FakeFeed();
    await _pumpCard(tester, feed, _item());
    expect(find.text('this is great'), findsOneWidget, reason: 'top comment preview on the card');

    await tester.tap(find.bySemanticsLabel('Comments'));
    await tester.pumpAndSettle();
    expect(find.text('Top'), findsOneWidget);
    expect(find.text('1 reply'), findsOneWidget);

    // Like the comment inside the sheet.
    await tester.tap(find.bySemanticsLabel('Like comment').first);
    await tester.pumpAndSettle();
    expect(feed.commentLikeCalls, [(1, true)]);

    // Expand the thread, then reply to the comment.
    await tester.tap(find.text('1 reply'));
    await tester.pumpAndSettle();
    expect(find.text('agreed'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Reply').first);
    await tester.pumpAndSettle();
    expect(find.text('Replying to @Aathi'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'me too');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(feed.added, [('me too', 1)]);
    expect(find.text('me too'), findsOneWidget, reason: 'the reply shows in its thread');

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsWidgets, reason: 'the card count follows what happened in the sheet');
  });

  testWidgets('a non-member sees the card and comments read-only', (tester) async {
    final feed = _FakeFeed()..canInteract = false;
    var joinTapped = false;
    await _pumpCard(tester, feed, _item(canInteract: false), onJoin: () => joinTapped = true);

    await tester.tap(find.bySemanticsLabel('Like'));
    await tester.pumpAndSettle();
    expect(feed.postLikeCalls, isEmpty);
    expect(find.text('Join the group to like, comment or share'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Join the group to like, comment or share'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Comments'));
    await tester.pumpAndSettle();
    expect(find.text('this is great'), findsWidgets, reason: 'comments stay readable');
    expect(find.byType(TextField), findsNothing, reason: 'no composer');
    expect(find.bySemanticsLabel('Reply'), findsNothing);
    await tester.tap(find.descendant(of: find.byType(CommentsPanel), matching: find.text('Join')));
    await tester.pumpAndSettle();
    expect(joinTapped, isTrue);
  });
}
