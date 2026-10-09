import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/auth/auth_scope.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/business/data/business_repository.dart';
import 'package:link_local/features/home/presentation/tabs/profile_tab.dart';
import 'package:link_local/features/messages/data/message_models.dart';
import 'package:link_local/features/messages/data/messages_repository.dart'
    show conversationsProvider, threadProvider, unreadCountProvider;
import 'package:link_local/features/messages/presentation/chat_screen.dart';
import 'package:link_local/features/orders/data/order_models.dart';
import 'package:link_local/features/orders/data/orders_repository.dart';
import 'package:link_local/features/orders/data/transaction_counts.dart';
import 'package:link_local/features/orders/presentation/payments_screen.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';

class _Account60 extends AuthScope {
  @override
  int? build() => 60;
}

class _SignedIn extends AuthController {
  _SignedIn(this.userType);
  final String userType;
  @override
  AuthState build() => AuthState(
    status: AuthStatus.authenticated,
    user: AppUser(id: 60, userType: userType, name: 'Simran'),
  );
}

/// [mine] are the member's own orders, [received] the ones they got as an SP. [seenAt] is the
/// server's "Payments last opened" time for this account (shared by all of their devices).
class _Server implements OrdersRepository {
  _Server(this.mine, this.received, {DateTime? seenAt}) : seenAt = seenAt ?? DateTime.now();
  final List<OrderModel> mine;
  final List<OrderModel> received;
  DateTime seenAt;
  bool seenFails = false;
  int marks = 0;

  @override
  Future<List<OrderModel>> myOrders() async => mine;
  @override
  Future<List<OrderModel>> incoming() async => received;
  @override
  Future<DateTime> paymentsSeenAt() async {
    if (seenFails) throw Exception('offline');
    return seenAt;
  }

  @override
  Future<DateTime> markPaymentsSeen() async {
    marks++;
    return seenAt = DateTime.now();
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// A payment made [ago] before now (or, with [at], at that moment).
OrderModel _order(int id, {String status = 'completed', List<Duration> paidAgo = const []}) => OrderModel.fromJson({
  'id': id,
  'status': status,
  'items': [],
  'payments': [
    for (final (i, ago) in paidAgo.indexed)
      {
        'id': id * 10 + i,
        'amount': 100,
        'paymentStatus': 'paid',
        'paidAt': DateTime.now().subtract(ago).toUtc().toIso8601String(),
      },
  ],
});

Conversation _chat(int other, {int unread = 0}) => Conversation.fromJson({
  'other': {'id': other},
  'unread': unread,
});

Future<_Server> _open(
  WidgetTester tester, {
  String userType = 'service_provider',
  List<OrderModel> mine = const [],
  List<OrderModel> received = const [],
  Future<List<Conversation>> Function()? chats,
  DateTime? seenAt,
  _Server? server,
  bool host = false,
}) async {
  server ??= _Server(mine, received, seenAt: seenAt);
  tester.view.physicalSize = const Size(1170, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final never = Completer<Never>().future;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authScopeProvider.overrideWith(_Account60.new),
        authControllerProvider.overrideWith(() => _SignedIn(userType)),
        ordersRepositoryProvider.overrideWithValue(server),
        conversationsProvider.overrideWith((ref) => chats?.call() ?? Future.value(const [])),
        myProfileProvider.overrideWith((ref) => never),
        myProviderFeaturesProvider.overrideWith((ref) => never),
        myAvailabilityProvider.overrideWith((ref) => never),
        threadProvider.overrideWith(
          (ref, otherId) async => ChatThread(otherId: otherId, otherName: 'Priya', messages: const []),
        ),
        unreadCountProvider.overrideWith((ref) async => 0),
      ],
      // [host]: start on a page with a button that opens the profile, so it can be left and
      // reopened.
      child: MaterialApp(
        home: host
            ? Builder(
                builder: (c) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const ProfileTab())),
                    child: const Text('open profile'),
                  ),
                ),
              )
            : const ProfileTab(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return server;
}

String? _count(String row) {
  final pill = find.byKey(ValueKey('count-$row'));
  if (pill.evaluate().isEmpty) return null;
  return (find.descendant(of: pill, matching: find.byType(Text)).evaluate().single.widget as Text).data;
}

const _hour = Duration(hours: 1);
const _day = Duration(days: 1);

/// Payments last opened two hours ago (on any device).
final _seenTwoHoursAgo = DateTime.now().subtract(_hour * 2);

void main() {
  group('what each count means', () {
    test('payments: only those after Payments was last opened, made or received', () {
      final seen = DateTime.now().subtract(_hour * 2);
      final mine = [_order(1, paidAgo: [_hour, _day])];
      final received = [_order(2, paidAgo: [_hour * 3, Duration.zero])];
      expect(newPaymentCount(mine, received, seen), 2);
    });
    test('orders: only in progress, placed + received, each order once', () {
      final mine = [_order(1, status: 'placed'), _order(2, status: 'completed'), _order(3, status: 'accepted')];
      final received = [_order(3, status: 'accepted'), _order(4, status: 'cancelled'), _order(5, status: 'rejected')];
      expect(inProgressOrderCount(mine, received), 2);
    });
    test('messages: unread messages across conversations', () {
      expect(unreadMessageCount([_chat(1, unread: 2), _chat(2), _chat(3, unread: 1)]), 3);
    });
  });

  testWidgets("the profile shows new payments, orders in progress and unread messages", (tester) async {
    await _open(
      tester,
      seenAt: _seenTwoHoursAgo,
      mine: [_order(1, status: 'accepted', paidAgo: [_hour]), _order(2, status: 'completed', paidAgo: [_day])],
      received: [_order(3, status: 'in_progress', paidAgo: [Duration.zero]), _order(4, status: 'completed')],
      chats: () async => [_chat(7, unread: 2), _chat(8), _chat(9, unread: 1)],
    );
    expect(_count('Payments'), '2');
    expect(_count('Order History'), '2');
    expect(_count('Messages'), '3');
  });

  testWidgets('a resident counts only their own orders', (tester) async {
    await _open(
      tester,
      userType: 'resident',
      mine: [_order(1, status: 'placed')],
      received: [_order(3, status: 'placed')],
    );
    expect(_count('Order History'), '1');
  });

  testWidgets('nothing to attend to shows no pills at all', (tester) async {
    await _open(
      tester,
      seenAt: _seenTwoHoursAgo,
      mine: [_order(1, paidAgo: [_day])],
      chats: () async => [_chat(7)],
    );
    expect(_count('Payments'), isNull);
    expect(_count('Order History'), isNull);
    expect(_count('Messages'), isNull);
  });

  testWidgets('a new account (seen = signup time) shows no old payments as new', (tester) async {
    await _open(tester, mine: [_order(1, paidAgo: [_day, _hour])]);
    expect(_count('Payments'), isNull);
  });

  testWidgets('opening Payments tells the server and clears the count', (tester) async {
    final server = await _open(tester, seenAt: _seenTwoHoursAgo, mine: [_order(1, paidAgo: [_hour])]);
    expect(_count('Payments'), '1');

    await tester.tap(find.text('Payments'));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(server.marks, 1);
    expect(server.seenAt.isAfter(_seenTwoHoursAgo), isTrue);
    expect(_count('Payments'), isNull);
  });

  testWidgets('another device: opening Payments there clears it here when the profile reopens', (tester) async {
    final server = _Server([_order(1, paidAgo: [_hour])], const [], seenAt: _seenTwoHoursAgo);
    await _open(tester, server: server, host: true);
    await tester.tap(find.text('open profile'));
    await tester.pumpAndSettle();
    expect(_count('Payments'), '1');
    Navigator.of(tester.element(find.byType(ProfileTab))).pop();
    await tester.pumpAndSettle();

    server.seenAt = DateTime.now(); // Payments opened on the other phone
    await tester.tap(find.text('open profile'));
    await tester.pumpAndSettle();
    expect(_count('Payments'), isNull);
    expect(server.marks, 0, reason: 'this device never opened Payments');
  });

  testWidgets("if the server's seen time can't load, no Payments count is shown", (tester) async {
    final server = _Server([_order(1, paidAgo: [_hour])], const [], seenAt: _seenTwoHoursAgo)..seenFails = true;
    await _open(tester, server: server);
    expect(_count('Payments'), isNull);
  });

  testWidgets('no count while loading or after a failure', (tester) async {
    final pending = Completer<List<Conversation>>();
    await _open(tester, chats: () => pending.future);
    expect(_count('Messages'), isNull);

    pending.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(_count('Messages'), isNull);
  });

  testWidgets('reading a chat (however it was opened) clears its unread messages', (tester) async {
    var unread = 2;
    await _open(tester, chats: () async => [_chat(7, unread: unread)]);
    expect(_count('Messages'), '2');

    unread = 0; // the server marks the thread read when it's loaded
    final nav = Navigator.of(tester.element(find.byType(ProfileTab)));
    nav.push(MaterialPageRoute(builder: (_) => const ChatScreen(otherUserId: 7, otherName: 'Priya')));
    await tester.pumpAndSettle();
    nav.pop();
    await tester.pumpAndSettle();
    expect(_count('Messages'), isNull);
  });
}
