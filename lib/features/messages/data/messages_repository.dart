import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/auth/auth_scope.dart';
import 'message_models.dart';

class MessagesRepository {
  MessagesRepository(this._dio);
  final Dio _dio;

  Future<List<Conversation>> conversations() async {
    final res = await _dio.get('/messages');
    return (res.data['data'] as List).map((e) => Conversation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ChatThread> thread(int otherUserId) async {
    final res = await _dio.get('/messages/$otherUserId');
    return ChatThread.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> send({
    required int receiverId,
    required String content,
    String? messageType,
    String? entityType,
    int? entityId,
  }) async {
    await _dio.post('/messages', data: {
      'receiverId': receiverId,
      'content': content,
      'messageType': ?messageType,
      'entityType': ?entityType,
      'entityId': ?entityId,
    });
  }

  Future<int> unreadCount() async {
    final res = await _dio.get('/messages/unread-count');
    return (res.data['data']['count'] as num?)?.toInt() ?? 0;
  }
}

final messagesRepositoryProvider =
    Provider<MessagesRepository>((ref) => MessagesRepository(ref.watch(dioProvider)));

/// The current user's conversation list.
final conversationsProvider =
    FutureProvider<List<Conversation>>((ref) {
  ref.bindToAccount();
  return ref.watch(messagesRepositoryProvider).conversations();
});

/// A chat thread with a specific user.
final threadProvider = FutureProvider.family<ChatThread, int>((ref, otherId) {
  ref.bindToAccount();
  return ref.watch(messagesRepositoryProvider).thread(otherId);
});

/// Total unread message count (for the badge).
final unreadCountProvider = FutureProvider<int>((ref) {
  ref.bindToAccount();
  return ref.watch(messagesRepositoryProvider).unreadCount();
});
