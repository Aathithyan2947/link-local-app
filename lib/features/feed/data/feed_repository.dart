import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'post_models.dart';

class FeedRepository {
  FeedRepository(this._dio);
  final Dio _dio;

  Future<List<PostItem>> posts({String? postType}) async {
    final res = await _dio.get('/posts', queryParameters: {
      'pageSize': 50,
      'postType': ?postType,
    });
    return (res.data['data'] as List)
        .map((e) => PostItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PostItem> post(int id) async {
    final res = await _dio.get('/posts/$id');
    return PostItem.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<PostItem> createPost({required String postType, String? text, List<String> photoUrls = const []}) async {
    final res = await _dio.post('/posts', data: {
      'postType': postType,
      if (text != null && text.trim().isNotEmpty) 'textContent': text.trim(),
      if (photoUrls.isNotEmpty)
        'media': photoUrls.map((u) => {'mediaType': 'photo', 'url': u}).toList(),
    });
    return PostItem.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<bool> toggleLike(int id) async {
    final res = await _dio.post('/posts/$id/like');
    return res.data['data']['liked'] as bool? ?? false;
  }

  Future<void> addComment(int id, String comment, {int? parentCommentId}) async {
    await _dio.post('/posts/$id/comments', data: {
      'comment': comment,
      'parentCommentId': ?parentCommentId,
    });
  }

  Future<void> sharePost(int id, {String channel = 'in_app'}) async {
    await _dio.post('/posts/$id/share', data: {'channel': channel});
  }
}

final feedRepositoryProvider = Provider<FeedRepository>((ref) => FeedRepository(ref.watch(dioProvider)));

/// The community feed (all post types).
final feedProvider = FutureProvider<List<PostItem>>((ref) => ref.watch(feedRepositoryProvider).posts());

/// A single post with its comments, keyed by post id.
final postDetailProvider =
    FutureProvider.family<PostItem, int>((ref, id) => ref.watch(feedRepositoryProvider).post(id));
