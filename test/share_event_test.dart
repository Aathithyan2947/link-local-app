import 'dart:async';

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
import 'package:link_local/features/members/data/members_repository.dart';
import 'package:link_local/features/messages/data/message_models.dart';
import 'package:link_local/features/messages/data/messages_repository.dart';
import 'package:link_local/features/messages/presentation/chat_screen.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

class _Messages implements MessagesRepository {
  final sent = <({int to, String content, String? entityType, int? entityId})>[];

  @override
  Future<List<Conversation>> conversations() async => [
        Conversation.fromJson({
          'other': {
            'id': 7,
            'profile': {'name': 'Priya'},
          },
          'lastMessage': 'hi',
        }),
      ];

  @override
  Future<void> send({
    required int receiverId,
    required String content,
    String? messageType,
    String? entityType,
    int? entityId,
  }) async =>
      sent.add((to: receiverId, content: content, entityType: entityType, entityId: entityId));

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _NoMembers implements MembersRepository {
  @override
  Future<MembersPage> list({required String scope, int? areaId, String? q, int page = 1, int pageSize = 30}) async =>
      const MembersPage(items: [], total: 0);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

final _event = EventDetail.fromJson({
  'id': 9,
  'title': 'Pottery for beginners',
  'date': '2030-11-01',
  'startTime': '1970-01-01T10:30:00.000Z',
  'mode': 'offline',
  'location': 'Pai Nagar Hall',
  'creator': {
    'id': 4,
    'profile': {'name': 'Asha'},
  },
});

void main() {
  testWidgets("BUG-100: an event's Share sends it into chats, as an event", (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final messages = _Messages();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        eventDetailProvider.overrideWith((ref, id) async => _event),
        messagesRepositoryProvider.overrideWithValue(messages),
        membersRepositoryProvider.overrideWithValue(_NoMembers()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const EventDetailScreen(id: 9)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsOneWidget, reason: 'the button used to do nothing');
    await tester.tap(find.text('Priya'));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    final m = messages.sent.single;
    expect((m.to, m.entityType, m.entityId, m.content), (7, 'event', 9, 'Shared an event'));
    expect(find.text('Sent to Priya'), findsOneWidget);
  });

  group('in the chat', () {
    Future<void> openChat(WidgetTester tester, Map<String, dynamic> message) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(Dio()),
          authControllerProvider.overrideWith(_SignedOut.new),
          threadProvider.overrideWith(
            (ref, id) async => ChatThread(otherId: id, otherName: 'Priya', messages: [ChatMessage.fromJson(message)]),
          ),
          conversationsProvider.overrideWith((ref) async => const []),
          unreadCountProvider.overrideWith((ref) async => 0),
          eventDetailProvider.overrideWith((ref, id) => Completer<EventDetail>().future),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ChatScreen(otherUserId: 7, otherName: 'Priya')),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a shared event shows as a card that opens the event', (tester) async {
      await openChat(tester, {
        'id': 1,
        'senderId': 7,
        'content': 'Shared an event',
        'entityType': 'event',
        'entityId': 9,
        'event': {
          'id': 9,
          'title': 'Pottery for beginners',
          'date': '2030-11-01',
          'startTime': '1970-01-01T10:30:00.000Z',
          'mode': 'offline',
          'location': 'Pai Nagar Hall',
          'hostName': 'Asha',
          'isActive': true,
        },
      });
      expect(find.text('Pottery for beginners'), findsOneWidget);
      expect(find.text('Fri, 1 Nov · 10:30 AM'), findsOneWidget);
      expect(find.text('Pai Nagar Hall'), findsOneWidget);
      expect(find.text('By: Asha'), findsOneWidget);
      expect(find.text('Shared an event'), findsNothing, reason: 'the placeholder note is not shown');

      await tester.tap(find.text('View event'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<EventDetailScreen>(find.byType(EventDetailScreen)).id, 9);
    });

    testWidgets('a removed event says so', (tester) async {
      await openChat(tester, {
        'id': 1,
        'senderId': 7,
        'content': 'Shared an event',
        'entityType': 'event',
        'entityId': 9,
        'event': null,
      });
      expect(find.text('This event is no longer available'), findsOneWidget);
    });
  });
}
