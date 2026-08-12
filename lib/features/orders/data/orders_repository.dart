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

  Future<void> pay(int id, {String paymentMethod = 'upi'}) async =>
      _dio.post('/orders/$id/pay', data: {'paymentType': 'advance', 'paymentMethod': paymentMethod});
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) => OrdersRepository(ref.watch(dioProvider)));

/// The current user's placed orders (buyer view).
final myOrdersProvider = FutureProvider<List<OrderModel>>((ref) {
  ref.bindToAccount();
  return ref.watch(ordersRepositoryProvider).myOrders();
});

/// Orders received by the current SP.
final incomingOrdersProvider =
    FutureProvider<List<OrderModel>>((ref) {
  ref.bindToAccount();
  return ref.watch(ordersRepositoryProvider).incoming();
});

/// A single order/booking by id (for the tracking screen).
final orderByIdProvider = FutureProvider.family<OrderModel, int>((ref, id) {
  ref.bindToAccount();
  return ref.watch(ordersRepositoryProvider).order(id);
});
