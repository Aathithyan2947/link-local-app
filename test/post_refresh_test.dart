import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/data/public_profile_models.dart';
import 'package:link_local/features/discovery/data/sp_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/feed/data/feed_repository.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/feed/presentation/create_post_screen.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

class _Feed implements FeedRepository {
  final created = <String>[];

  @override
  Future<PostItem> createPost({required String postType, String? text, List<String> photoUrls = const []}) async {
    created.add(text ?? '');
    return PostItem.fromJson({'id': 99, 'postType': postType, 'textContent': text});
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

void main() {
  testWidgets('a new post refreshes Home, Posts and the profiles — no pull-to-refresh', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final loads = <String, int>{};
    void load(String what) => loads[what] = (loads[what] ?? 0) + 1;
    final feed = _Feed();
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        feedRepositoryProvider.overrideWithValue(feed),
        feedProvider.overrideWith((ref) async {
          load('posts');
          return const [];
        }),
        homeFeedProvider.overrideWith((ref) {
          load('home');
          return Completer<HomeFeed>().future; // its content doesn't matter here
        }),
        discussionsSectionScopedProvider.overrideWith((ref, areaId) async {
          load('home discussions');
          return const [];
        }),
        serviceProviderDetailProvider.overrideWith((ref, id) async {
          load('provider profile');
          return ServiceProviderDetail.fromJson({'id': id, 'name': 'Asha'});
        }),
        publicProfileProvider.overrideWith((ref, id) async {
          load('member profile');
          return PublicProfile.fromJson({'id': id, 'name': 'Asha'});
        }),
      ],
    );
    addTearDown(container.dispose);

    // Everything a new post shows in has been opened once already (and is cached).
    for (final p in [
      homeFeedProvider,
      feedProvider,
      discussionsSectionScopedProvider('3'),
      serviceProviderDetailProvider(60),
      publicProfileProvider(60),
    ]) {
      container.listen(p, (_, _) {});
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CreatePostScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, {'home': 1, 'posts': 1, 'home discussions': 1, 'provider profile': 1, 'member profile': 1});

    await tester.enterText(find.byType(TextField), 'testing post 3');
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(feed.created, ['testing post 3']);
    expect(
      loads,
      {'home': 2, 'posts': 2, 'home discussions': 2, 'provider profile': 2, 'member profile': 2},
      reason: 'each list reloads on its own',
    );
  });
}
