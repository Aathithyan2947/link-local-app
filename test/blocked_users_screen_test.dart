import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/data/blocked_user_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/profile/presentation/blocked_users_screen.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

class _Discovery implements DiscoveryRepository {
  final blocked = <BlockedUserItem>[
    const BlockedUserItem(userId: 50, name: 'Simran 3', role: 'Haircare Salon', location: 'Gadhav Naka'),
  ];

  @override
  Future<List<BlockedUserItem>> listBlockedUsers() async => List.of(blocked);

  @override
  Future<void> unblockUser(int userId) async => blocked.removeWhere((u) => u.userId == userId);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

void main() {
  testWidgets('a blocked provider is listed (with the real app theme) and can be unblocked', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = _Discovery();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(Dio()),
          authControllerProvider.overrideWith(_SignedOut.new),
          discoveryRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const BlockedUsersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'the row must lay out');
    expect(find.text('Simran 3'), findsOneWidget);
    expect(find.text('Haircare Salon · Gadhav Naka'), findsOneWidget);

    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    expect(find.text('Simran 3'), findsNothing);
    expect(find.text('No blocked users.'), findsOneWidget);
  });
}
