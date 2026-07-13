import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'order_models.dart';

class OrdersRepository {
  OrdersRepository(this._dio);
  final Dio _dio;

  Future<OrderModel> placeOrder(Map<String, dynamic> data) async {
    final res = await _dio.post('/orders', data: data);
    return OrderModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

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

  Future<void> pay(int id) async => _dio.post('/orders/$id/pay', data: {'paymentType': 'advance'});
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) => OrdersRepository(ref.watch(dioProvider)));

/// The current user's placed orders (buyer view).
final myOrdersProvider = FutureProvider<List<OrderModel>>((ref) => ref.watch(ordersRepositoryProvider).myOrders());

/// Orders received by the current SP.
final incomingOrdersProvider =
    FutureProvider<List<OrderModel>>((ref) => ref.watch(ordersRepositoryProvider).incoming());
