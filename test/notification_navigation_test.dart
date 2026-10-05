import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/presentation/event_detail_screen.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/feed/presentation/post_detail_screen.dart';
import 'package:link_local/features/messages/data/message_models.dart';
import 'package:link_local/features/messages/data/messages_repository.dart' show threadProvider;
import 'package:link_local/features/messages/presentation/chat_screen.dart';
import 'package:link_local/features/notifications/data/notification_models.dart';
import 'package:link_local/features/notifications/data/notifications_repository.dart';
import 'package:link_local/features/notifications/presentation/notification_navigation.dart';
import 'package:link_local/features/notifications/presentation/notifications_screen.dart';
import 'package:link_local/features/orders/presentation/order_tracking_screen.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

class _FakeNotifications implements NotificationsRepository {
  final markedRead = <int>[];

  @override
  Future<void> markRead(int id) async => markedRead.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

AppNotification _n(int id, String title, {String? entityType, int? entityId, String type = 'message'}) =>
    AppNotification.fromJson({
      'id': id,
      'title': title,
      'notificationType': type,
      'entityType': entityType,
      'entityId': entityId,
      'isRead': false,
    });

Future<_FakeNotifications> _open(WidgetTester tester, List<AppNotification> items) async {
  final repo = _FakeNotifications();
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        notificationsRepositoryProvider.overrideWithValue(repo),
        notificationsProvider.overrideWith((ref) async => items),
        unreadCountProvider.overrideWith((ref) async => items.length),
        // The customer (user 77) who sent the message.
        threadProvider.overrideWith(
          (ref, otherId) async => ChatThread(otherId: otherId, otherName: 'Priya Customer', messages: const []),
        ),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('a message notification opens the chat with the person who sent it', (tester) async {
    final repo = await _open(tester, [_n(1, 'New message from Priya Customer', entityType: 'message', entityId: 77)]);

    await tester.tap(find.text('New message from Priya Customer'));
    await tester.pumpAndSettle();

    final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.otherUserId, 77, reason: "the notification's entityId is the sender");
    expect(chat.otherName, 'Priya Customer');
    expect(repo.markedRead, [1]);
  });

  testWidgets('an enquiry notification opens the same chat', (tester) async {
    await _open(tester, [
      _n(2, 'New enquiry from Priya Customer', type: 'enquiry', entityType: 'message', entityId: 77),
    ]);
    await tester.tap(find.text('New enquiry from Priya Customer'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).otherUserId, 77);
  });

  testWidgets('a notification with nowhere to go is just marked read', (tester) async {
    final repo = await _open(tester, [_n(3, 'Welcome to Link Local', type: 'system')]);
    await tester.tap(find.text('Welcome to Link Local'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(repo.markedRead, [3]);
  });

  group('notificationScreen', () {
    test('comment → the post', () {
      final s = notificationScreen(_n(1, 'New comment', entityType: 'post', entityId: 11));
      expect(s, isA<PostDetailScreen>().having((w) => w.id, 'id', 11));
    });
    test('event / group → their pages', () {
      expect(
        notificationScreen(_n(1, 'x', entityType: 'event', entityId: 5)),
        isA<EventDetailScreen>().having((w) => w.id, 'id', 5),
      );
      expect(
        notificationScreen(_n(1, 'x', entityType: 'group', entityId: 10)),
        isA<GroupProfileScreen>().having((w) => w.id, 'id', 10),
      );
    });
    test('order → the order, as before', () {
      expect(
        notificationScreen(_n(1, 'x', entityType: 'order', entityId: 9)),
        isA<OrderTrackingScreen>().having((w) => w.orderId, 'orderId', 9),
      );
    });
    test('unknown or missing target → none', () {
      expect(notificationScreen(_n(1, 'x', entityType: 'mystery', entityId: 1)), isNull);
      expect(notificationScreen(_n(1, 'x', entityType: 'post')), isNull);
      expect(notificationHasTarget(_n(1, 'x', entityType: 'message', entityId: 77)), isTrue);
    });
  });
}
