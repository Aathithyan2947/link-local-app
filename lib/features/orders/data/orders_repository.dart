import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/auth/auth_scope.dart';
import 'order_models.dart';

class OrdersRepository {
  OrdersRepository(this._dio);
  final Dio _dio;

  Future<OrderModel> placeOrder(Map<String, dynamic> data) async {
    final res = await _dio.post('/orders', data: data);
    return OrderModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Sends a service booking request (free; SP accepts before the resident pays).
  Future<OrderModel> placeBooking(Map<String, dynamic> data) async {
    final res = await _dio.post('/orders/bookings', data: data);
    return OrderModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Instant "pay this provider" for non-menu (service) SPs — no request/accept step.
  /// The resident enters the amount themselves (negotiated directly with the SP).
  Future<OrderModel> createDirectPayment(int spProfileId, double amount) async {
    final res = await _dio.post('/orders/direct-payment', data: {'spProfileId': spProfileId, 'amount': amount});
    return OrderModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Cart/booking fee breakdown + coupon preview (no persistence).
  Future<OrderQuote> quote(Map<String, dynamic> data) async {
    final res = await _dio.post('/orders/quote', data: data);
    return OrderQuote.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> accept(int id) async => _dio.post('/orders/$id/accept');
  Future<void> reject(int id, {String? reason}) async =>
      _dio.post('/orders/$id/reject', data: {'reason': ?reason});

  Future<List<OrderModel>> myOrders() async {
    final res = await _dio.get('/orders/mine');
    return (res.data['data'] as List).map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<OrderModel>> incoming() async {
    final res = await _dio.get('/orders/incoming');
    return (res.data['data'] as List).map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<OrderModel> order(int id) async {
    final res = await _dio.get('/orders/$id');
    return OrderModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> updateStatus(int id, String status, {String? reason}) async {
    await _dio.patch('/orders/$id/status', data: {'status': status, 'reason': ?reason});
  }

  Future<void> pay(int id, {String paymentMethod = 'upi', String? paymentSubMethod}) async => _dio.post(
        '/orders/$id/pay',
        data: {'paymentType': 'advance', 'paymentMethod': paymentMethod, 'paymentSubMethod': ?paymentSubMethod},
      );
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) => OrdersRepository(ref.watch(dioProvider)));

/// The current user's placed orders (buyer view).
final myOrdersProvider = FutureProvider<List<OrderModel>>((ref) {
  ref.bindToAccount();
  return ref.watch(ordersRepositoryProvider).myOrders();
});

/// Orders received by the current SP — one list behind both "Your Orders & Bookings" and
/// Order History, so a status change shows in both.
class IncomingOrders extends AsyncNotifier<List<OrderModel>> {
  @override
  Future<List<OrderModel>> build() {
    ref.bindToAccount();
    return ref.watch(ordersRepositoryProvider).incoming();
  }

  /// Shows [status] for order [id] at once (before the server's reply). A refetch replaces it
  /// with the server's copy; on failure, invalidating the provider restores the truth.
  void setStatusLocally(int id, String status) {
    final list = state.asData?.value;
    if (list == null) return;
    state = AsyncData([for (final o in list) o.id == id ? o.withStatus(status) : o]);
  }
}

final incomingOrdersProvider = AsyncNotifierProvider<IncomingOrders, List<OrderModel>>(IncomingOrders.new);

/// Orders with a provider action (accept, mark completed, …) still in flight. Their buttons
/// show a spinner and ignore further taps, and Order History holds off reloading meanwhile so
/// it can't briefly undo a status shown ahead of the server's reply.
class OrderActionsInFlight extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  /// False when [id] already has an action running.
  bool tryStart(int id) {
    if (state.contains(id)) return false;
    state = {...state, id};
    return true;
  }

  void finish(int id) => state = {...state}..remove(id);
}

final orderActionsInFlightProvider = NotifierProvider<OrderActionsInFlight, Set<int>>(OrderActionsInFlight.new);

/// A single order/booking by id (for the tracking screen). Auto-disposed, so every visit loads
/// the current order — a kept copy would show a booking as "Confirmed" after it was completed.
final orderByIdProvider = FutureProvider.autoDispose.family<OrderModel, int>((ref, id) {
  ref.bindToAccount();
  return ref.watch(ordersRepositoryProvider).order(id);
});
