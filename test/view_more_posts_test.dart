import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/data/public_profile_models.dart';
import 'package:link_local/features/discovery/data/sp_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/discovery/presentation/user_profile_screen.dart';
import 'package:link_local/features/feed/data/feed_repository.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/feed/presentation/user_posts_screen.dart';
import 'package:link_local/features/orders/data/orders_repository.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

const _author = 50;

Map<String, dynamic> _post(int id, String text) => {
  'id': id,
  'postType': 'ask_help',
  'textContent': text,
  'createdAt': '2026-10-09T10:00:00.000Z',
  'user': {
    'id': _author,
    'profile': {'name': 'Aathi testing'},
  },
};

/// The author's 4 posts; the profiles show only the latest few.
final _all = [_post(4, 'testing 3'), _post(3, 'testing post 2'), _post(2, 'testing post 1'), _post(1, 'first post')];

class _Feed implements FeedRepository {
  final askedFor = <int>[];

  @override
  Future<List<PostItem>> postsBy(int userId) async {
    askedFor.add(userId);
    return _all.map(PostItem.fromJson).toList();
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<_Feed> _open(WidgetTester tester, Widget profile) async {
  tester.view.physicalSize = const Size(1170, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final feed = _Feed();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        feedRepositoryProvider.overrideWithValue(feed),
        myOrdersProvider.overrideWith((ref) async => const []),
        serviceProviderDetailProvider.overrideWith(
          (ref, id) async => ServiceProviderDetail.fromJson({
            'id': 5,
            'name': 'Aathi testing',
            'user': {'id': _author},
            'posts': _all.take(2).toList(),
          }),
        ),
        publicProfileProvider.overrideWith(
          (ref, id) async => PublicProfile.fromJson({
            'id': 8,
            'name': 'Aathi testing',
            'user': {'id': _author, 'userType': 'resident'},
            'posts': _all.take(3).toList(),
          }),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: profile),
    ),
  );
  await tester.pumpAndSettle();
  return feed;
}

Future<void> _viewMore(WidgetTester tester) async {
  await tester.ensureVisible(find.text('View More'));
  await tester.tap(find.text('View More'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("provider profile: View More opens all of that person's posts", (tester) async {
    final feed = await _open(tester, const ServiceProviderDetailScreen(id: 5));
    expect(find.text('first post'), findsNothing, reason: 'the profile shows only the latest two');

    await _viewMore(tester);

    expect(find.byType(UserPostsScreen), findsOneWidget);
    expect(feed.askedFor, [_author], reason: "the posts are that member's, by user id");
    expect(find.text('by Aathi testing'), findsOneWidget);
    for (final t in ['testing 3', 'testing post 2', 'testing post 1', 'first post']) {
      await tester.scrollUntilVisible(find.text(t), 200);
      expect(find.text(t), findsOneWidget);
    }
  });

  testWidgets('member profile: View More works there too', (tester) async {
    final feed = await _open(tester, const UserProfileScreen(id: 8));
    await _viewMore(tester);
    expect(find.byType(UserPostsScreen), findsOneWidget);
    expect(feed.askedFor, [_author]);
  });
}
