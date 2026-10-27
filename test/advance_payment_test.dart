import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/address/data/address_models.dart';
import 'package:link_local/features/address/data/address_repository.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/business/data/product_models.dart';
import 'package:link_local/features/discovery/data/sp_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/orders/data/advance_terms.dart';
import 'package:link_local/features/orders/data/cart.dart';
import 'package:link_local/features/orders/data/order_models.dart';
import 'package:link_local/features/orders/data/orders_repository.dart';
import 'package:link_local/features/orders/presentation/cart_review_screen.dart';
import 'package:link_local/features/orders/presentation/order_success_screen.dart';
import 'package:link_local/features/orders/presentation/order_tracking_screen.dart';
import 'package:link_local/features/payments/presentation/payment_method_screen.dart';
import 'package:link_local/features/services/data/service_profile_repository.dart';
import 'package:link_local/features/services/presentation/category_fields_form_screen.dart';

CustomField _answer(String name, String value, {String category = 'delivery', String type = 'text', int id = 1}) =>
    CustomField(
      fieldId: id,
      subcategoryName: 'Home baker',
      category: category,
      fieldName: name,
      fieldType: type,
      isRequired: false,
      value: value,
    );

class _Buyer extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 5, userType: 'resident', name: 'Asha', hasAddress: true, isVerified: true),
      );
}

/// A seller (profile 7) with one ₹1,000 cake; [quoteJson] is their advance terms.
class _Orders implements OrdersRepository {
  _Orders(this.terms);
  final Map<String, dynamic> terms;
  int placed = 0;

  @override
  Future<OrderQuote> quote(Map<String, dynamic> data) async => OrderQuote.fromJson({
        'subtotal': 980,
        'deliveryCharge': 0,
        'packagingCharge': 0,
        'platformFee': 20,
        'discount': 0,
        'total': 1000,
        ...terms,
      });

  @override
  Future<OrderModel> placeOrder(Map<String, dynamic> data) async {
    placed++;
    final advance = (terms['advanceAmount'] as num).toDouble();
    final payLater = terms['payLater'] == true;
    return OrderModel.fromJson({
      'id': 12,
      'orderKind': 'product',
      'status': 'placed',
      'totalAmount': 1000,
      'amountDue': payLater ? 1000 : advance,
      'amountPaid': 0,
      'balanceDue': 1000,
      'advancePercent': terms['advancePercent'],
      'payLater': payLater,
      'spProfile': {'id': 7, 'userId': 70, 'name': 'Meera Bakes'},
      'buyer': {'id': 5},
      'payments': const [],
    });
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<void> _openCart(WidgetTester tester, Map<String, dynamic> terms) async {
  tester.view.physicalSize = const Size(1800, 5000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final orders = _Orders(terms);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_Buyer.new),
      ordersRepositoryProvider.overrideWithValue(orders),
      myAddressProofProvider.overrideWith((ref) async => const AddressProofInfo(hasAddress: true, status: 'approved')),
      serviceProviderDetailProvider.overrideWith((ref, id) async => ServiceProviderDetail.fromJson({'id': 7, 'name': 'Meera Bakes'})),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const CartReviewScreen()),
  ));
  final container = ProviderScope.containerOf(tester.element(find.byType(CartReviewScreen)));
  container.read(cartProvider.notifier).add(7, 'Meera Bakes', const SpProduct(id: 1, name: 'Chocolate cake', price: 980));
  await tester.pumpAndSettle();
}

Future<void> _placeOrder(WidgetTester tester, String button) async {
  await tester.ensureVisible(find.textContaining('Today,').first);
  await tester.tap(find.textContaining('Today,').first);
  await tester.pump();
  await tester.tap(find.text(button));
  await tester.pumpAndSettle();
}

OrderModel _order({required double paid, bool payLater = false, String status = 'confirmed'}) => OrderModel.fromJson({
      'id': 12,
      'orderKind': 'product',
      'status': status,
      'totalAmount': 1000,
      'amountDue': paid > 0 ? 1000 - paid : (payLater ? 1000 : 500),
      'amountPaid': paid,
      'balanceDue': 1000 - paid,
      'advancePercent': payLater ? 0 : 50,
      'payLater': payLater,
      'spProfile': {'id': 7, 'userId': 70, 'name': 'Meera Bakes'},
      'buyer': {'id': 5},
      'payments': [
        if (paid > 0) {'amount': paid, 'paymentStatus': 'paid', 'paymentMethod': 'upi'},
      ],
    });

Future<void> _openTracking(WidgetTester tester, OrderModel order) async {
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_Buyer.new),
      orderByIdProvider.overrideWith((ref, id) async => order),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const OrderTrackingScreen(orderId: 12)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group("BUG-097: reading a provider's advance terms", () {
    test('the three ways providers set it', () {
      expect(advancePercentOf([_answer('Advanced Payment Settings', 'Percentage Based'), _answer('Advance percentage', '50')]), 50);
      expect(advancePercentOf([_answer('How much advance do you need?', 'Percentage Based'), _answer('Advance percentage', '20%')]), 20);
      expect(advancePercentOf([_answer('Advance payment', '50% advance', category: 'basic_details')]), 50);
    });

    test('"No Advance" wins over a leftover percentage; bad or missing answers mean none', () {
      expect(advancePercentOf([_answer('Advanced Payment Settings', 'No Advance'), _answer('Advance percentage', '50')]), 0);
      expect(advancePercentOf([_answer('Advanced Payment Settings', 'Percentage Based'), _answer('Advance percentage', '500')]), isNull);
      expect(advancePercentOf([_answer('How many hours in advance should an order be placed?', '48 hours pior')]), isNull);
      expect(advancePercentOf(const []), isNull);
    });

    test('an advance percentage answer must be 1 to 100', () {
      expect(advancePercentError('50'), isNull);
      expect(advancePercentError('50%'), isNull);
      expect(advancePercentError(''), isNull);
      expect(advancePercentError('500'), 'Advance percentage must be between 1 and 100');
      expect(advancePercentError('0'), 'Advance percentage must be between 1 and 100');
    });

    test('an order from an older backend counts one payment as settling it', () {
      final o = OrderModel.fromJson({
        'id': 1,
        'totalAmount': 300,
        'payments': [
          {'amount': 300, 'paymentStatus': 'paid'},
        ],
      });
      expect(o.fullyPaid, isTrue);
      expect(o.hasBalance, isFalse);
    });
  });

  group('BUG-097: checkout', () {
    testWidgets('a 50% advance: the cart says what is paid now and later, and charges ₹500', (tester) async {
      await _openCart(tester, {'advancePercent': 50, 'advanceAmount': 500, 'payLater': false});
      expect(find.text('Pay now (50% advance)'), findsOneWidget);
      expect(find.text('Pay later'), findsOneWidget);
      expect(find.text('₹500'), findsNWidgets(2));

      await _placeOrder(tester, 'Confirm  ·  Pay ₹500 now');
      final payment = tester.widget<PaymentMethodScreen>(find.byType(PaymentMethodScreen));
      expect(payment.total, 500, reason: 'the advance, not the ₹1,000 total');
    });

    testWidgets("a seller who takes no advance: the order is placed without paying", (tester) async {
      await _openCart(tester, {'advancePercent': 0, 'advanceAmount': 0, 'payLater': true});
      expect(find.text('Pay now'), findsOneWidget);
      expect(find.text('₹0'), findsOneWidget);

      await _placeOrder(tester, 'Confirm  ·  Pay later');
      expect(find.byType(PaymentMethodScreen), findsNothing);
      expect(find.byType(OrderSuccessScreen), findsOneWidget);
      expect(find.textContaining('Pay ₹1000 later from My Orders'), findsOneWidget);
    });

    testWidgets('no advance terms: everything at checkout, as before', (tester) async {
      await _openCart(tester, {'advancePercent': 100, 'advanceAmount': 1000, 'payLater': false});
      expect(find.text('Pay later'), findsNothing);
      await _placeOrder(tester, 'Confirm  ·  ₹1000');
      expect(tester.widget<PaymentMethodScreen>(find.byType(PaymentMethodScreen)).total, 1000);
    });
  });

  group('BUG-097: paying the balance', () {
    testWidgets('after the advance, Order Tracking shows what is due and pays the balance', (tester) async {
      await _openTracking(tester, _order(paid: 500));
      expect(find.text('Advance ₹500 paid · ₹500 due'), findsOneWidget);
      await tester.tap(find.text('Pay balance  ·  ₹500'));
      await tester.pumpAndSettle();
      expect(tester.widget<PaymentMethodScreen>(find.byType(PaymentMethodScreen)).total, 500);
    });

    testWidgets('a no-advance order is paid in full from Order Tracking', (tester) async {
      await _openTracking(tester, _order(paid: 0, payLater: true));
      expect(find.text('To be paid later · ₹1000'), findsOneWidget);
      expect(find.text('Pay  ·  ₹1000'), findsOneWidget);
    });

    testWidgets('a fully paid order has nothing to pay', (tester) async {
      await _openTracking(tester, _order(paid: 1000));
      expect(find.text('Paid'), findsOneWidget);
      expect(find.textContaining('Pay '), findsNothing);
    });

    testWidgets('a cancelled order offers no payment', (tester) async {
      await _openTracking(tester, _order(paid: 500, status: 'cancelled'));
      expect(find.textContaining('Pay balance'), findsNothing);
    });
  });

  testWidgets('BUG-097: the setup form refuses an advance percentage over 100', (tester) async {
    tester.view.physicalSize = const Size(1800, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final services = _Fields([
      _answer('Advanced Payment Settings', 'Percentage Based', type: 'dropdown', id: 1)..value = 'Percentage Based',
      CustomField(
        fieldId: 2,
        subcategoryName: 'Home baker',
        category: 'delivery',
        fieldName: 'Advance percentage',
        fieldType: 'number',
        isRequired: false,
        dependsOnFieldId: 1,
        dependsOnValue: 'Percentage Based',
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [dioProvider.overrideWithValue(Dio()), serviceProfileRepositoryProvider.overrideWithValue(services)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoryFieldsFormScreen(category: 'delivery', categoryLabel: 'Delivery')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Between 1 and 100'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Advance percentage'), '500');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Advance percentage must be between 1 and 100'), findsOneWidget);
    expect(services.saved, isEmpty);
  });
}

class _Fields implements ServiceProfileRepository {
  _Fields(this.fields);
  final List<CustomField> fields;
  final saved = <List<Map<String, dynamic>>>[];

  @override
  Future<List<CustomField>> getCustomFields() async => fields;
  @override
  Future<void> saveCustomFields(List<Map<String, dynamic>> values) async => saved.add(values);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}
