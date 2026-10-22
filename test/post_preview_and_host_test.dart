import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/data/event_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/event_detail_screen.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/feed/presentation/widgets/discussion_card.dart';
import 'package:link_local/features/feed/presentation/widgets/post_card.dart';
import 'package:link_local/features/home/data/home_models.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

final _long = List.filled(60, 'Technology keeps changing how neighbours help each other.').join(' ');

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1170, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_SignedOut.new),
    ],
    child: MaterialApp(theme: AppTheme.light, home: Scaffold(body: ListView(children: [child]))),
  ));
  await tester.pumpAndSettle();
}

Text _postText(WidgetTester tester) => tester.widget<Text>(find.text(_long));

void main() {
  group('a long post is a preview on cards, in full on its page', () {
    final post = PostItem.fromJson({
      'id': 31,
      'postType': 'share_update',
      'textContent': _long,
      'user': {'id': 60, 'profile': {'name': 'Keerthi Testing'}},
    });

    testWidgets('feed card (opens the post): limited lines', (tester) async {
      await _pump(tester, PostCard(post: post, onOpen: () {}));
      expect(_postText(tester).maxLines, kPostPreviewLines);
      expect(_postText(tester).overflow, TextOverflow.ellipsis);
    });

    testWidgets('the post page itself: everything', (tester) async {
      await _pump(tester, PostCard(post: post));
      expect(_postText(tester).maxLines, isNull);
    });

    testWidgets('Home / group discussion card: limited lines', (tester) async {
      final item = DiscussionItem.fromJson({
        'id': 31,
        'postType': 'share_update',
        'textContent': _long,
        'user': {'id': 60, 'profile': {'name': 'Keerthi Testing'}},
      });
      await _pump(tester, DiscussionCard(item: item, onOpen: () {}));
      expect(_postText(tester).maxLines, kPostPreviewLines);
    });
  });

  group("the host's location on an event", () {
    EventDetail event({required bool viewerIsHost, bool withAddress = true}) => EventDetail.fromJson({
          'id': 9,
          'title': 'workshop on road bikes',
          'date': '2030-11-01',
          'isHost': viewerIsHost,
          'creator': {
            'id': 4,
            'profile': {
              'name': 'Keerthi Testing',
              // What the API sends: the whole address to the host, the neighbourhood otherwise.
              'address': viewerIsHost && withAddress
                  ? {
                      'fullAddress': 'no 512/29, Raunak Maximum City, Near D-Mart, Anand Nagar, Thane',
                      'area': {'areaName': 'Ghodbunder Road', 'city': {'name': 'Mumbai'}},
                    }
                  : {
                      'area': {'areaName': 'Anand Nagar', 'city': {'name': 'Mumbai'}},
                    },
            },
          },
        });

    Future<void> open(WidgetTester tester, EventDetail e) async {
      tester.view.physicalSize = const Size(1170, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(Dio()),
          authControllerProvider.overrideWith(_SignedOut.new),
          eventDetailProvider.overrideWith((ref, id) async => e),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const EventDetailScreen(id: 9)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the host sees their own saved address, as on My Profile', (tester) async {
      await open(tester, event(viewerIsHost: true));
      expect(find.text('no 512/29, Raunak Maximum City, Near D-Mart, Anand Nagar, Thane'), findsOneWidget);
      expect(find.text('Ghodbunder Road, Mumbai'), findsNothing);
    });

    testWidgets('anyone else sees the neighbourhood and city', (tester) async {
      await open(tester, event(viewerIsHost: false));
      expect(find.text('Anand Nagar, Mumbai'), findsOneWidget);
      expect(find.textContaining('Raunak'), findsNothing);
    });
  });
}
