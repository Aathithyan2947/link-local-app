import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/router/app_router.dart' show appRouteObserver;
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/data/public_profile_models.dart';
import 'package:link_local/features/discovery/data/sp_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/discovery/presentation/user_profile_screen.dart';
import 'package:link_local/features/messages/data/message_models.dart';
import 'package:link_local/features/messages/data/messages_repository.dart';
import 'package:link_local/features/messages/presentation/chat_screen.dart';
import 'package:link_local/features/orders/data/orders_repository.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

const _sp = 50; // the provider's user id (profile #5)

/// One customer ↔ provider pair on a fake server: block rows both ways, and the messages sent.
class _Server {
  bool iBlocked = false;
  bool theyBlocked = false;
  bool blockOnNextSend = false; // a block lands while the chat is open
  Duration blockDelay = const Duration(milliseconds: 100); // how long Block / Unblock take
  bool blockFails = false;
  int profileFetches = 0;
  final sent = <String>[];

  DioException _forbidden(String message) {
    final req = RequestOptions(path: '/messages');
    return DioException(
      requestOptions: req,
      response: Response(requestOptions: req, statusCode: 403, data: {'success': false, 'message': message}),
      type: DioExceptionType.badResponse,
    );
  }
}

class _Messages implements MessagesRepository {
  _Messages(this.s);
  final _Server s;

  @override
  Future<ChatThread> thread(int otherUserId) async => ChatThread(
    otherId: otherUserId,
    otherName: 'Simran',
    messages: [const ChatMessage(id: 1, senderId: _sp, content: 'Hello, how can I help?')],
    blockedByMe: s.iBlocked,
    blockedByThem: s.theyBlocked,
  );

  @override
  Future<List<Conversation>> conversations() async => const [];

  @override
  Future<void> send({
    required int receiverId,
    required String content,
    String? messageType,
    String? entityType,
    int? entityId,
  }) async {
    if (s.blockOnNextSend) s.iBlocked = true;
    if (s.iBlocked) throw s._forbidden("You've blocked this person. Unblock them to send messages.");
    if (s.theyBlocked) throw s._forbidden("You can't message this person.");
    s.sent.add(content);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Discovery implements DiscoveryRepository {
  _Discovery(this.s);
  final _Server s;

  /// Like the real network: each request takes a moment, and reads what the server holds
  /// at the moment it arrives.
  @override
  Future<ServiceProviderDetail> serviceProvider(int id) async {
    s.profileFetches++;
    final blocked = s.iBlocked;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _detail(blocked);
  }

  ServiceProviderDetail _detail(bool blocked) => ServiceProviderDetail.fromJson({
    'id': 5,
    'name': 'Simran 3',
    'isBlocked': blocked,
    'user': {'id': _sp},
  });

  /// A member's profile (#8, user 50), with whether the viewer has blocked them.
  @override
  Future<PublicProfile> publicProfile(int id) async {
    final blocked = s.iBlocked;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return PublicProfile.fromJson({
      'id': 8,
      'name': 'Ravi',
      'isBlocked': blocked,
      'user': {'id': _sp, 'userType': 'resident'},
    });
  }

  @override
  Future<void> blockUser(int userId, {String? reason}) async {
    await Future<void>.delayed(s.blockDelay);
    if (s.blockFails) throw Exception('offline');
    s.iBlocked = true;
  }

  @override
  Future<void> unblockUser(int userId) async {
    await Future<void>.delayed(s.blockDelay);
    if (s.blockFails) throw Exception('offline');
    s.iBlocked = false;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<void> _pump(WidgetTester tester, _Server s, Widget home) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        messagesRepositoryProvider.overrideWithValue(_Messages(s)),
        discoveryRepositoryProvider.overrideWithValue(_Discovery(s)),
        myOrdersProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(theme: AppTheme.light, home: home, navigatorObservers: [appRouteObserver]),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openChat(WidgetTester tester, _Server s) =>
    _pump(tester, s, const ChatScreen(otherUserId: _sp, otherName: 'Simran'));

Future<void> _openProfile(WidgetTester tester, _Server s) => _pump(tester, s, const ServiceProviderDetailScreen(id: 5));

final _composer = find.widgetWithText(TextField, 'Message…');

void main() {
  testWidgets('a provider I blocked: history stays, the composer is replaced, Unblock restores it', (tester) async {
    final s = _Server()..iBlocked = true;
    await _openChat(tester, s);

    expect(find.text('Hello, how can I help?'), findsOneWidget, reason: 'past messages stay readable');
    expect(_composer, findsNothing);
    expect(find.text('You blocked Simran.'), findsOneWidget);

    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    expect(s.iBlocked, isFalse);
    expect(_composer, findsOneWidget);
    expect(find.text('You blocked Simran.'), findsNothing);
  });

  testWidgets("when they blocked me I just can't reply (it doesn't say they blocked me)", (tester) async {
    final s = _Server()..theyBlocked = true;
    await _openChat(tester, s);
    expect(_composer, findsNothing);
    expect(find.text("You can't reply to this conversation."), findsOneWidget);
    expect(find.text('Unblock'), findsNothing);
  });

  testWidgets("a block while the chat is open: the server's reason shows and the chat locks", (tester) async {
    final s = _Server()..blockOnNextSend = true;
    await _openChat(tester, s);
    await tester.enterText(_composer, 'are you free tomorrow?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(s.sent, isEmpty);
    expect(find.text("You've blocked this person. Unblock them to send messages."), findsOneWidget);
    expect(find.text('Could not send'), findsNothing);
    expect(find.text('You blocked Simran.'), findsOneWidget);
  });

  testWidgets('not blocked: chatting works as before', (tester) async {
    final s = _Server();
    await _openChat(tester, s);
    await tester.enterText(_composer, 'hi');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(s.sent, ['hi']);
  });

  group('provider profile', () {
    testWidgets('blocked: no Message / Enquire / Make Payment, a note with Unblock instead', (tester) async {
      final s = _Server()..iBlocked = true;
      await _openProfile(tester, s);
      expect(find.text("You've blocked this provider"), findsOneWidget);
      expect(find.text('Enquire'), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
      expect(find.text('Make Payment'), findsNothing);

      await tester.tap(find.text('Unblock'));
      await tester.pumpAndSettle();
      expect(find.text('Enquire'), findsOneWidget);
      expect(find.text('Make Payment'), findsOneWidget);
    });

    testWidgets("blocking from the menu locks the chat, even one that's already loaded", (tester) async {
      final s = _Server();
      await _openProfile(tester, s);
      final container = ProviderScope.containerOf(tester.element(find.byType(ServiceProviderDetailScreen)));
      // The chat was opened earlier and is cached.
      final sub = container.listen(threadProvider(_sp), (_, _) {});
      addTearDown(sub.close);
      await container.read(threadProvider(_sp).future);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Block'));
      await tester.pumpAndSettle();

      expect(find.text("You've blocked this provider"), findsOneWidget);
      expect((await container.read(threadProvider(_sp).future)).blockedByMe, isTrue);

      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing, reason: 'no chat button once blocked');
    });
  });

  group('member profile', () {
    Future<void> openMember(WidgetTester tester, _Server s) => _pump(tester, s, const UserProfileScreen(id: 8));
    final message = find.widgetWithText(ElevatedButton, 'Message');

    testWidgets('Block reloads the page in place: Unblock label, Message replaced by the note', (tester) async {
      final s = _Server();
      await openMember(tester, s);
      expect(message, findsOneWidget);

      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Block').last); // confirm
      await tester.pumpAndSettle();

      expect(s.iBlocked, isTrue);
      expect(find.text("You've blocked Ravi"), findsOneWidget, reason: 'no pull-to-refresh needed');
      expect(message, findsNothing);
      expect(find.text('Block'), findsNothing);
      expect(find.text('Unblock'), findsNWidgets(2), reason: 'header button and the note');
    });

    testWidgets('Unblock brings Message back straight away', (tester) async {
      final s = _Server()..iBlocked = true;
      await openMember(tester, s);
      expect(message, findsNothing);

      await tester.tap(find.text('Unblock').last);
      await tester.pumpAndSettle();
      expect(s.iBlocked, isFalse);
      expect(message, findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
    });
  });

  group('speed', () {
    Future<void> blockFromMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Block')); // confirm
      await tester.pump(); // the dialog closes…
      await tester.pump(const Duration(milliseconds: 300)); // …and its exit animation ends
    }

    testWidgets('the profile switches as soon as Block is confirmed, before the server answers', (tester) async {
      final s = _Server()..blockDelay = const Duration(seconds: 3);
      await _openProfile(tester, s);
      await blockFromMenu(tester);

      expect(s.iBlocked, isFalse, reason: 'the server has not answered yet');
      expect(find.text("You've blocked this provider"), findsOneWidget);
      expect(find.text('Enquire'), findsNothing);
      await tester.pump(const Duration(seconds: 3)); // the server answers
      await tester.pumpAndSettle();
      expect(s.iBlocked, isTrue);
      expect(find.text("You've blocked this provider"), findsOneWidget);
    });

    testWidgets('closing the menu and the dialog no longer reloads the whole profile', (tester) async {
      final s = _Server();
      await _openProfile(tester, s);
      final before = s.profileFetches;
      await blockFromMenu(tester);
      await tester.pumpAndSettle();
      expect(s.profileFetches - before, 1, reason: 'one background refresh after the block, nothing else');
    });

    testWidgets('if blocking fails, the profile switches back and says so', (tester) async {
      final s = _Server()..blockFails = true;
      await _openProfile(tester, s);
      await blockFromMenu(tester);
      await tester.pumpAndSettle();

      expect(find.text("You've blocked this provider"), findsNothing);
      expect(find.text('Enquire'), findsOneWidget);
      expect(find.text('Could not block Simran 3. Try again.'), findsOneWidget);
    });

    testWidgets('a slow reload started before the block cannot undo it on screen', (tester) async {
      final s = _Server();
      await _openProfile(tester, s);
      final container = ProviderScope.containerOf(tester.element(find.byType(ServiceProviderDetailScreen)));
      container.invalidate(serviceProviderDetailProvider(5)); // a reload reads "not blocked"…
      await tester.pump();
      await blockFromMenu(tester);
      await tester.pumpAndSettle(); // …and lands after the block
      expect(find.text("You've blocked this provider"), findsOneWidget);
    });
  });
}
