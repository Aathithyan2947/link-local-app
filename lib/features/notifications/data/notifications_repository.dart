import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'notification_models.dart';

class NotificationsRepository {
  NotificationsRepository(this._dio);
  final Dio _dio;

  Future<List<AppNotification>> list() async {
    final res = await _dio.get('/notifications');
    return (res.data['data'] as List).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<int> unreadCount() async {
    final res = await _dio.get('/notifications/unread-count');
    return (res.data['data']['count'] as num).toInt();
  }

  Future<void> markRead(int id) async => _dio.patch('/notifications/$id/read');
  Future<void> markAllRead() async => _dio.patch('/notifications/read-all');
}

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) => NotificationsRepository(ref.watch(dioProvider)));

final notificationsProvider =
    FutureProvider<List<AppNotification>>((ref) => ref.watch(notificationsRepositoryProvider).list());

final unreadCountProvider =
    FutureProvider<int>((ref) => ref.watch(notificationsRepositoryProvider).unreadCount());
