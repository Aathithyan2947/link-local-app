import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/feed/data/feed_repository.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/feed/presentation/create_post_screen.dart';
import 'package:link_local/features/feed/presentation/widgets/discussion_card.dart';
import 'package:link_local/features/feed/presentation/widgets/post_card.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

class _Feed implements FeedRepository {
  final sent = <Map<String, Object?>>[];

  @override
  Future<PostItem> createPost({
    required String postType,
    String? title,
    String? text,
    String? audience,
    bool notifyReplies = true,
    List<PostMedia> media = const [],
  }) async {
    sent.add({'postType': postType, 'title': title, 'text': text, 'audience': audience, 'notify': notifyReplies});
    return PostItem.fromJson({'id': 1, 'postType': postType});
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Map<String, dynamic> _address({String? building = 'Shree Ganesh Apartments', String? lane = 'Lane 2'}) => {
      'apartment': building,
      'lane1': lane,
      'area': {
        'areaName': 'South Delhi',
        'city': {'id': 4, 'name': 'Delhi'},
      },
    };

Future<_Feed> _open(WidgetTester tester, {Map<String, dynamic>? address}) async {
  tester.view.physicalSize = const Size(1800, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final feed = _Feed();
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_SignedOut.new),
      feedRepositoryProvider.overrideWithValue(feed),
      myProfileProvider.overrideWith(
          (ref) async => ProfileDetail.fromJson({'id': 1, 'name': 'Asha', 'address': address ?? _address()})),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const CreatePostScreen()),
  ));
  await tester.pumpAndSettle();
  return feed;
}

Finder get _body => find.widgetWithText(TextField, 'Write your post....');
Finder get _titleField => find.widgetWithText(TextField, "What's your post about?");

void main() {
  group('BUG-115: "Post in" picks who the post is for', () {
    testWidgets('defaults to the member\'s area, by name', (tester) async {
      await _open(tester);
      expect(find.text('Post in: '), findsOneWidget);
      expect(find.text('South Delhi'), findsOneWidget);
    });

    testWidgets('offers building, lane, area and city by name, and sends the pick', (tester) async {
      final feed = await _open(tester);
      await tester.tap(find.byKey(const ValueKey('audience-picker')));
      await tester.pumpAndSettle();
      for (final t in ['My Society', 'My Lane', 'My Area', 'My City', 'Shree Ganesh Apartments', 'Lane 2', 'Delhi']) {
        expect(find.text(t), findsWidgets, reason: '$t is offered');
      }
      await tester.tap(find.text('My Lane'));
      await tester.pumpAndSettle();
      expect(find.text('Lane 2'), findsOneWidget, reason: 'the header now says Post in: Lane 2');

      await tester.enterText(_body, 'Anyone on the lane free on Sunday?');
      await tester.tap(find.text('Post Discussion'));
      await tester.pumpAndSettle();
      expect(feed.sent.single['audience'], 'lane');
    });

    testWidgets('no building on the address: no My Society option', (tester) async {
      await _open(tester, address: _address(building: null));
      await tester.tap(find.byKey(const ValueKey('audience-picker')));
      await tester.pumpAndSettle();
      expect(find.text('My Society'), findsNothing);
      expect(find.text('My Lane'), findsOneWidget);
    });
  });

  group('BUG-108: Write a Post follows the Figma', () {
    testWidgets('title (optional, counted to 100), type, text and notify are sent', (tester) async {
      final feed = await _open(tester);
      expect(find.text('0/100'), findsOneWidget);
      await tester.enterText(_titleField, 'Looking for a Home Tutor');
      await tester.pump();
      expect(find.text('24/100'), findsOneWidget);

      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Query').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.enterText(_body, 'For class 8 maths, weekday evenings.');
      await tester.tap(find.text('Post Discussion'));
      await tester.pumpAndSettle();

      expect(feed.sent.single, {
        'postType': 'query',
        'title': 'Looking for a Home Tutor',
        'text': 'For class 8 maths, weekday evenings.',
        'audience': 'area',
        'notify': false,
      });
    });

    testWidgets('the title stops at 100 characters', (tester) async {
      await _open(tester);
      await tester.enterText(_titleField, 'x' * 130);
      await tester.pump();
      expect(find.text('100/100'), findsOneWidget);
    });

    testWidgets('a title on its own is enough to post; nothing at all is not', (tester) async {
      final feed = await _open(tester);
      await tester.tap(find.text('Post Discussion'));
      await tester.pump();
      expect(find.text('Write something or add a photo or video'), findsOneWidget);
      expect(feed.sent, isEmpty);

      await tester.enterText(_titleField, 'Lost cat near Gate 2');
      await tester.tap(find.text('Post Discussion'));
      await tester.pumpAndSettle();
      expect(feed.sent.single['title'], 'Lost cat near Gate 2');
      expect(feed.sent.single['notify'], true, reason: 'notify me of replies is on by default');
    });

    testWidgets('the Figma\'s add-media row and notify switch are there', (tester) async {
      await _open(tester);
      expect(find.text('Add Photo or Video'), findsOneWidget);
      expect(find.text('Add supporting files to explain'), findsOneWidget);
      expect(find.text('Notify me of replies'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });
  });

  group('BUG-108: titles and videos on cards', () {
    Future<void> pumpCard(WidgetTester tester, Widget card) async {
      tester.view.physicalSize = const Size(1800, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(Dio()),
          authControllerProvider.overrideWith(_SignedOut.new),
        ],
        child: MaterialApp(theme: AppTheme.light, home: Scaffold(body: SingleChildScrollView(child: card))),
      ));
      await tester.pump();
    }

    testWidgets('a post card shows the title, and a video with a play button', (tester) async {
      final post = PostItem.fromJson({
        'id': 5,
        'postType': 'help',
        'title': 'Free plants',
        'textContent': 'Take them from the lobby.',
        'media': [
          {'mediaType': 'video', 'url': 'https://res.cloudinary.com/demo/video/upload/v1/plants.mp4'},
        ],
      });
      expect(post.media.single.videoPoster, 'https://res.cloudinary.com/demo/video/upload/v1/plants.jpg');
      await pumpCard(tester, PostCard(post: post));
      expect(find.text('Free plants'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget, reason: 'the type chip uses the new labels');
      expect(find.bySemanticsLabel('Play video'), findsOneWidget);
    });

    testWidgets('a discussion card (Home, feed) shows the title above the text', (tester) async {
      final item = DiscussionItem.fromJson({
        'id': 6,
        'title': 'Looking for a Yoga Trainer',
        'textContent': 'Mornings, near the park.',
        'user': {
          'id': 2,
          'profile': {'name': 'Ayush'},
        },
      });
      await pumpCard(tester, DiscussionCard(item: item, onOpen: () {}));
      expect(find.text('Looking for a Yoga Trainer'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Looking for a Yoga Trainer')).dy,
        lessThan(tester.getTopLeft(find.text('Mornings, near the park.')).dy),
      );
    });

    test('older post types still read as labels', () {
      expect(PostItem.fromJson({'id': 1, 'postType': 'buy_sell'}).typeLabel, 'Buy / Sell');
      expect(PostItem.fromJson({'id': 1, 'postType': 'recommendation'}).typeLabel, 'Recommendation');
    });
  });
}
