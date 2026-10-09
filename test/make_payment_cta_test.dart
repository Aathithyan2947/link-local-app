import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/data/sp_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/orders/data/order_models.dart';
import 'package:link_local/features/orders/data/orders_repository.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

/// SP profile #5 (user 50), as a resident sees it.
ServiceProviderDetail _sp({bool hasMenu = false}) => ServiceProviderDetail.fromJson({
  'id': 5,
  'name': 'Simran 3',
  'hasMenu': hasMenu,
  'user': {'id': 50},
});

OrderModel _order(String status, {bool paid = false}) => OrderModel.fromJson({
  'id': 9,
  'status': status,
  'spProfile': {'id': 5},
  'items': [],
  'payments': [
    if (paid) {'id': 1, 'amount': 100, 'paymentStatus': 'paid'},
  ],
  'totalAmount': 100,
  'paidAmount': paid ? 100 : 0,
});

Future<void> _open(WidgetTester tester, ServiceProviderDetail sp, {List<OrderModel> orders = const []}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox()); // a fresh scope for each case
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        serviceProviderDetailProvider.overrideWith((ref, id) async => sp),
        myOrdersProvider.overrideWith((ref) async => orders),
      ],
      child: const MaterialApp(home: ServiceProviderDetailScreen(id: 5)),
    ),
  );
  await tester.pumpAndSettle();
}

final _cta = find.widgetWithText(OutlinedButton, 'Make Payment');

void main() {
  testWidgets('Make Payment is a visible button, and no longer in the three-dot menu', (tester) async {
    await _open(tester, _sp());
    expect(_cta, findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Report\nAbuse'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Make\nPayment'), findsNothing);
    expect(find.text('Make Payment'), findsOneWidget, reason: 'only the button');
  });

  testWidgets('for a service provider it opens the amount sheet', (tester) async {
    await _open(tester, _sp());
    await tester.tap(_cta);
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid amount'), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('for a menu provider it shows only while an accepted order awaits payment', (tester) async {
    await _open(tester, _sp(hasMenu: true));
    expect(_cta, findsNothing, reason: 'nothing to pay for');

    await _open(tester, _sp(hasMenu: true), orders: [_order('pending')]);
    expect(_cta, findsNothing, reason: 'not accepted yet');

    await _open(tester, _sp(hasMenu: true), orders: [_order('accepted', paid: true)]);
    expect(_cta, findsNothing, reason: 'already paid');

    await _open(tester, _sp(hasMenu: true), orders: [_order('accepted')]);
    expect(_cta, findsOneWidget);
  });
}
