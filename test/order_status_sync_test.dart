import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/orders/data/order_models.dart';
import 'package:link_local/features/orders/data/orders_repository.dart';
import 'package:link_local/features/orders/presentation/incoming_orders_screen.dart';
import 'package:link_local/features/orders/presentation/order_history_screen.dart';
import 'package:link_local/features/orders/presentation/order_tracking_screen.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

/// One confirmed booking (#42) on a fake server. `gate` holds the status update open so a
/// test can look at the screen before the server answers; `refuse` makes it fail.
class _Server implements OrdersRepository {
  String status = 'confirmed';
  int updateCalls = 0;
  int detailFetches = 0;
  Completer<void>? gate;
  bool refuse = false;

  Map<String, dynamic> get _json => {
    'id': 42,
    'orderKind': 'booking',
    'status': status,
    'placedAt': '2026-10-04T10:00:00.000Z',
    'buyer': {
      'id': 7,
      'profile': {'name': 'Priya'},
    },
    'items': [],
    'payments': [],
  };

  @override
  Future<List<OrderModel>> incoming() async => [OrderModel.fromJson(_json)];

  @override
  Future<OrderModel> order(int id) async {
    detailFetches++;
    return OrderModel.fromJson(_json);
  }

  @override
  Future<void> updateStatus(int id, String s, {String? reason}) async {
    updateCalls++;
    if (gate != null) await gate!.future;
    if (refuse) throw Exception('server says no');
    status = s;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

late ProviderContainer _container;

Future<void> _start(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  _container = ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_SignedOut.new),
      ordersRepositoryProvider.overrideWithValue(server),
    ],
  );
  addTearDown(_container.dispose);
  Widget button(String label, Widget screen) => Builder(
    builder: (c) => TextButton(
      onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => screen)),
      child: Text(label),
    ),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              button('open booking', const OrderTrackingScreen(orderId: 42)),
              button('open incoming', const IncomingOrdersScreen()),
              button('open history', const OrderHistoryScreen()),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _go(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

String? _historyStatus() => _container.read(incomingOrdersProvider).asData?.value.firstWhere((o) => o.id == 42).status;

void main() {
  testWidgets("the tester's flow: a booking opened before completing shows Completed afterwards", (tester) async {
    final server = _Server();
    await _start(tester, server);

    await _go(tester, 'open booking'); // step 3: open the booking (Confirmed)
    expect(_container.read(orderByIdProvider(42)).value?.status, 'confirmed');
    await _back(tester);

    await _go(tester, 'open incoming');
    await _go(tester, 'Mark completed');
    expect(find.text('Marked as completed'), findsOneWidget);
    await _back(tester);

    await _go(tester, 'open history');
    expect(find.text('Completed'), findsWidgets, reason: 'Order History lists it as Completed');
    await tester.tap(find.text('Priya'));
    await tester.pumpAndSettle();
    expect(server.detailFetches, 2, reason: 'the detail loads fresh each time it opens');
    expect(_container.read(orderByIdProvider(42)).value?.status, 'completed');
  });

  testWidgets('Mark completed moves the booking at once, before the server replies; double taps are ignored', (
    tester,
  ) async {
    final server = _Server()..gate = Completer<void>();
    await _start(tester, server);
    await _go(tester, 'open incoming');

    await tester.tap(find.text('Mark completed'));
    await tester.pump(); // server hasn't answered yet
    expect(_historyStatus(), 'completed', reason: 'shown completed straight away');
    expect(find.text('Mark completed'), findsNothing, reason: 'no longer an ongoing order');

    // A second tap on the (now gone) button can't fire a second request.
    expect(server.updateCalls, 1);

    server.gate!.complete();
    await tester.pumpAndSettle();
    expect(server.updateCalls, 1);
    expect(_historyStatus(), 'completed');
  });

  testWidgets('if the server refuses, the booking goes back to ongoing with an error', (tester) async {
    final server = _Server()
      ..gate = Completer<void>()
      ..refuse = true;
    await _start(tester, server);
    await _go(tester, 'open incoming');

    await tester.tap(find.text('Mark completed'));
    await tester.pump();
    expect(_historyStatus(), 'completed');

    server.gate!.complete();
    await tester.pumpAndSettle();
    expect(_historyStatus(), 'confirmed', reason: "the server's copy replaces the optimistic one");
    expect(find.text('Mark completed'), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
  });
}
