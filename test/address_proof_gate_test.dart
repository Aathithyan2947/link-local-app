import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/api_exception.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/address/data/address_models.dart';
import 'package:link_local/features/address/data/address_repository.dart';
import 'package:link_local/features/address/presentation/address_proof_gate.dart';
import 'package:link_local/features/address/presentation/address_proof_screen.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/discovery/data/group_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/feed/data/feed_repository.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/feed/presentation/widgets/discussion_card.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';

class _Member extends AuthController {
  _Member({this.verified = false});
  final bool verified;
  @override
  AuthState build() => AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 5, userType: 'resident', name: 'Asha', hasAddress: true, isVerified: verified),
      );
}

/// Records whether the gated action went ahead.
class _Groups implements DiscoveryRepository {
  int joins = 0;
  Object? reject;

  @override
  Future<String?> joinGroup(int id) async {
    joins++;
    if (reject != null) throw reject!;
    return 'joined';
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// One post with one comment; records likes and comments that reach the "server".
class _Feed implements FeedRepository {
  final postLikes = <bool>[];
  final commentLikes = <bool>[];
  final added = <String>[];
  Object? reject;

  @override
  Future<({bool liked, int likes})> setLike(int id, bool liked) async {
    if (reject != null) throw reject!;
    postLikes.add(liked);
    return (liked: liked, likes: liked ? 1 : 0);
  }

  @override
  Future<({bool liked, int likes})> setCommentLike(int commentId, bool liked) async {
    commentLikes.add(liked);
    return (liked: liked, likes: liked ? 1 : 0);
  }

  @override
  Future<CommentPage> comments(int postId, {String sort = 'top', int page = 1, int pageSize = 20}) async => CommentPage(
        items: [PostComment(id: 1, comment: 'this is great', authorName: 'Ravi', createdAt: DateTime.now())],
        hasMore: false,
        totalComments: 1,
        canInteract: true,
      );

  @override
  Future<PostComment> addComment(int id, String comment, {int? parentCommentId}) async {
    added.add(comment);
    return PostComment(id: 9, comment: comment, authorName: 'Asha', createdAt: DateTime.now());
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// A 403 the way the backend refuses for want of a proof.
DioException _proofRefusal() {
  final req = RequestOptions(path: '/groups/3/join');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: 403, data: {
      'success': false,
      'message': 'Upload your address proof to join a group.',
      'code': 'ADDRESS_PROOF_REQUIRED',
    }),
    type: DioExceptionType.badResponse,
  );
}

Future<List<bool>> _pump(
  WidgetTester tester, {
  required String status,
  bool verified = false,
  bool proofLoads = true,
}) async {
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final results = <bool>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(() => _Member(verified: verified)),
      myAddressProofProvider.overrideWith((ref) async {
        if (!proofLoads) throw ApiException('Your internet seems to be a bit wonky.');
        return AddressProofInfo(hasAddress: true, fullAddress: 'Flat 2, Pai Nagar', status: status);
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(
            onPressed: () async => results.add(await ensureAddressProof(context, ref, action: 'submit a review')),
            child: const Text('Review'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Review'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  group('BUG-084: the address proof popup', () {
    testWidgets('matches the design, names the action, and Not now cancels it', (tester) async {
      final results = await _pump(tester, status: 'none');
      expect(find.text('Address proof mandatory'), findsOneWidget);
      expect(find.text('Upload your address proof to submit a review.'), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
      expect(find.text('Upload address proof'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Address proof mandatory'), findsNothing);
      expect(results, [false], reason: 'the action does not go ahead');
    });

    testWidgets('Upload address proof opens the upload screen', (tester) async {
      await _pump(tester, status: 'none');
      await tester.tap(find.text('Upload address proof'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressProofScreen), findsOneWidget);
    });

    testWidgets('a rejected proof asks again', (tester) async {
      await _pump(tester, status: 'rejected');
      expect(find.text('Address proof mandatory'), findsOneWidget);
    });

    testWidgets('a proof under review, or an approved one, lets the member go ahead', (tester) async {
      expect(await _pump(tester, status: 'pending'), [true]);
      expect(find.text('Address proof mandatory'), findsNothing);
      expect(await _pump(tester, status: 'approved'), [true]);
    });

    testWidgets('a member an admin verified is never asked', (tester) async {
      expect(await _pump(tester, status: 'none', verified: true), [true]);
      expect(find.text('Address proof mandatory'), findsNothing);
    });

    testWidgets("when the status can't be loaded, the server decides", (tester) async {
      expect(await _pump(tester, status: 'none', proofLoads: false), [true]);
    });
  });

  group('BUG-084: the server refusing for want of a proof', () {
    test('is recognised from a raw Dio error and from an ApiException', () {
      final dio = _proofRefusal();
      expect(ApiException.fromDio(dio).code, ApiException.addressProofRequired);
      expect(ApiException.fromDio(dio).message, 'Upload your address proof to join a group.');
    });

    testWidgets('shows the popup; any other error is left to the caller', (tester) async {
      final handled = <bool>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(children: [
              TextButton(
                onPressed: () => handled.add(handleAddressProofError(context, Exception('x'), action: 'join a group')),
                child: const Text('other'),
              ),
              TextButton(
                onPressed: () => handled.add(handleAddressProofError(context, _proofRefusal(), action: 'join a group')),
                child: const Text('proof'),
              ),
            ]),
          ),
        ),
      ));
      await tester.tap(find.text('other'));
      await tester.pumpAndSettle();
      expect(find.text('Address proof mandatory'), findsNothing);
      await tester.tap(find.text('proof'));
      await tester.pumpAndSettle();
      expect(handled, [false, true]);
      expect(find.text('Upload your address proof to join a group.'), findsOneWidget);
    });
  });

  group('BUG-084: joining a group', () {
    Future<_Groups> openGroup(WidgetTester tester, {required String status}) async {
      tester.view.physicalSize = const Size(1800, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final groups = _Groups();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(Dio()),
          authControllerProvider.overrideWith(_Member.new),
          myAddressProofProvider.overrideWith((ref) async => AddressProofInfo(hasAddress: true, status: status)),
          discoveryRepositoryProvider.overrideWithValue(groups),
          groupDetailProvider.overrideWith((ref, id) async => GroupDetail.fromJson({
                'id': 3,
                'title': 'Morning Runners',
                'creator': {
                  'profile': {'name': 'Ravi'},
                },
                '_count': {'members': 4},
              })),
          homeFeedProvider.overrideWith((ref) => Completer<HomeFeed>().future),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const GroupProfileScreen(id: 3)),
      ));
      await tester.pumpAndSettle();
      return groups;
    }

    testWidgets('without a proof the popup shows and nothing is sent', (tester) async {
      final groups = await openGroup(tester, status: 'none');
      await tester.tap(find.text('Join Group'));
      await tester.pumpAndSettle();
      expect(find.text('Upload your address proof to join a group.'), findsOneWidget);
      expect(groups.joins, 0);
    });

    testWidgets('with a proof under review it joins', (tester) async {
      final groups = await openGroup(tester, status: 'pending');
      await tester.tap(find.text('Join Group'));
      await tester.pump();
      expect(groups.joins, 1);
      expect(find.text('Address proof mandatory'), findsNothing);
    });

    testWidgets("if the server still refuses, it's the popup rather than 'Something went wrong'", (tester) async {
      final groups = await openGroup(tester, status: 'pending');
      groups.reject = _proofRefusal();
      await tester.tap(find.text('Join Group'));
      await tester.pumpAndSettle();
      expect(find.text('Address proof mandatory'), findsOneWidget);
      expect(find.text('Something went wrong'), findsNothing);
    });
  });

  group('BUG-084: liking and commenting (the user\'s call, 2026-10-27)', () {
    /// Ravi's post on Home. [status] null: the proof status hasn't loaded yet.
    Future<_Feed> openPost(WidgetTester tester, {String? status}) async {
      tester.view.physicalSize = const Size(1800, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final feed = _Feed();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(Dio()),
          authControllerProvider.overrideWith(_Member.new),
          feedRepositoryProvider.overrideWithValue(feed),
          myAddressProofProvider.overrideWith((ref) => status == null
              ? Completer<AddressProofInfo>().future
              : Future.value(AddressProofInfo(hasAddress: true, status: status))),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          // Home loads the proof status at start (its upload reminder), before any post shows.
          home: Consumer(
            builder: (_, ref, child) {
              ref.watch(myAddressProofProvider);
              return child!;
            },
            child: Scaffold(
            body: ListView(children: [
              DiscussionCard(
                item: DiscussionItem(
                    id: 11, text: 'Lost keys near the park', authorName: 'Ravi', likes: 0, comments: 1,
                    createdAt: DateTime.now()),
              ),
            ]),
          ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return feed;
    }

    testWidgets("without a proof the heart doesn't move and nothing is sent", (tester) async {
      final feed = await openPost(tester, status: 'none');
      await tester.tap(find.bySemanticsLabel('Like'));
      await tester.pumpAndSettle();
      expect(find.text('Upload your address proof to like a post.'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(feed.postLikes, isEmpty);
    });

    testWidgets('with a proof under review it likes at once', (tester) async {
      final feed = await openPost(tester, status: 'pending');
      await tester.tap(find.bySemanticsLabel('Like'));
      await tester.pumpAndSettle();
      expect(feed.postLikes, [true]);
      expect(find.text('Address proof mandatory'), findsNothing);
    });

    testWidgets('before the status loads, a server refusal shows the popup and the heart goes back', (tester) async {
      final feed = await openPost(tester);
      feed.reject = _proofRefusal();
      await tester.tap(find.bySemanticsLabel('Like'));
      await tester.pumpAndSettle();
      expect(find.text('Address proof mandatory'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets("the comment box doesn't open without a proof; tapping it says why", (tester) async {
      final feed = await openPost(tester, status: 'rejected');
      await tester.tap(find.bySemanticsLabel('Comments'));
      await tester.pumpAndSettle();
      final box = find.widgetWithText(TextField, 'Add a comment…');
      expect(tester.widget<TextField>(box).readOnly, isTrue);

      await tester.tap(box);
      await tester.pumpAndSettle();
      expect(find.text('Upload your address proof to comment on a post.'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Like comment').first);
      await tester.pumpAndSettle();
      expect(find.text('Upload your address proof to like a comment.'), findsOneWidget);
      expect(feed.commentLikes, isEmpty);
      expect(feed.added, isEmpty);
    });

    testWidgets('with a proof the comment goes through', (tester) async {
      final feed = await openPost(tester, status: 'approved');
      await tester.tap(find.bySemanticsLabel('Comments'));
      await tester.pumpAndSettle();
      final box = find.widgetWithText(TextField, 'Add a comment…');
      expect(tester.widget<TextField>(box).readOnly, isFalse);
      await tester.enterText(box, 'I saw them at the gate');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(feed.added, ['I saw them at the gate']);
    });
  });
}
