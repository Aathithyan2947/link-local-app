import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/business/data/business_repository.dart';
import 'package:link_local/features/feed/data/feed_repository.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/feed/presentation/feed_screen.dart';
import 'package:link_local/features/feed/presentation/user_posts_screen.dart';
import 'package:link_local/features/home/presentation/tabs/profile_tab.dart';
import 'package:link_local/features/messages/data/messages_repository.dart' show conversationsProvider;
import 'package:link_local/features/orders/data/orders_repository.dart';
import 'package:link_local/features/orders/data/transaction_counts.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';

const _me = 60;

class _SignedIn extends AuthController {
  @override
  AuthState build() => const AuthState(
    status: AuthStatus.authenticated,
    user: AppUser(id: _me, userType: 'resident', name: 'Aathi testing'),
  );
}

/// The Payments badge isn't what this test is about: its "seen" time never arrives.
class _SeenPending extends PaymentsSeenAt {
  @override
  Future<DateTime> build() => Completer<DateTime>().future;
}

class _Feed implements FeedRepository {
  final askedFor = <int>[];

  @override
  Future<List<PostItem>> postsBy(int userId) async {
    askedFor.add(userId);
    return [
      PostItem.fromJson({
        'id': 4,
        'postType': 'ask_help',
        'textContent': 'testing 3',
        'user': {
          'id': userId,
          'profile': {'name': 'Aathi testing'},
        },
      }),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

void main() {
  testWidgets('Profile → My Posts opens my own posts, not the community feed', (tester) async {
    tester.view.physicalSize = const Size(1170, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final feed = _Feed();
    final never = Completer<Never>().future;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(Dio()),
          authControllerProvider.overrideWith(_SignedIn.new),
          feedRepositoryProvider.overrideWithValue(feed),
          myOrdersProvider.overrideWith((ref) async => const []),
          conversationsProvider.overrideWith((ref) async => const []),
          paymentsSeenAtProvider.overrideWith(_SeenPending.new),
          myProfileProvider.overrideWith((ref) => never),
          myProviderFeaturesProvider.overrideWith((ref) => never),
          myAvailabilityProvider.overrideWith((ref) => never),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ProfileTab()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Posts'));
    await tester.pumpAndSettle();

    expect(find.byType(FeedScreen), findsNothing);
    final screen = tester.widget<UserPostsScreen>(find.byType(UserPostsScreen));
    expect(screen.userId, _me);
    expect(screen.mine, isTrue);
    expect(feed.askedFor, [_me], reason: 'only my posts are requested');
    expect(find.text('My Posts'), findsOneWidget, reason: 'the title');
    expect(find.text('testing 3'), findsOneWidget);
    expect(find.text('Post'), findsOneWidget, reason: 'a button to write a new one');
  });
}
