import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/auth/auth_scope.dart';
import '../../home/data/home_repository.dart';
import 'post_models.dart';

class FeedRepository {
  FeedRepository(this._dio);
  final Dio _dio;

  /// The community feed, scoped like Home: [scope] is the member's society / lane / area /
  /// city, and [areaId] a picked area.
  Future<List<PostItem>> posts({String? postType, String? scope, int? areaId}) async {
    final res = await _dio.get('/posts', queryParameters: {
      'pageSize': 50,
      'postType': ?postType,
      'scope': ?scope,
      'areaId': ?areaId,
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

  /// Posts a comment, or a reply when [parentCommentId] is set; returns it as saved.
  Future<PostComment> addComment(int id, String comment, {int? parentCommentId}) async {
    final res = await _dio.post('/posts/$id/comments', data: {
      'comment': comment,
      'parentCommentId': ?parentCommentId,
    });
    return PostComment.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Sets the viewer's like on a post. Idempotent: sending the same state twice changes
  /// nothing, so rapid taps can't stack likes.
  Future<({bool liked, int likes})> setLike(int id, bool liked) async {
    final res = await _dio.put('/posts/$id/like', data: {'liked': liked});
    return _likeResult(res.data['data'] as Map<String, dynamic>);
  }

  /// Sets the viewer's like on a comment or reply (idempotent, like [setLike]).
  Future<({bool liked, int likes})> setCommentLike(int commentId, bool liked) async {
    final res = await _dio.put('/posts/comments/$commentId/like', data: {'liked': liked});
    return _likeResult(res.data['data'] as Map<String, dynamic>);
  }

  ({bool liked, int likes}) _likeResult(Map<String, dynamic> d) =>
      (liked: d['liked'] as bool? ?? false, likes: (d['likes'] as num?)?.toInt() ?? 0);

  /// One page of a post's top-level comments: `top` (most-liked first) or `newest`.
  Future<CommentPage> comments(int postId, {String sort = 'top', int page = 1, int pageSize = 20}) async {
    final res = await _dio.get('/posts/$postId/comments',
        queryParameters: {'sort': sort, 'page': page, 'pageSize': pageSize});
    return CommentPage.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// A comment's replies, oldest first.
  Future<List<PostComment>> replies(int commentId) async {
    final res = await _dio.get('/posts/comments/$commentId/replies');
    return ((res.data['data'] as List?) ?? [])
        .map((e) => PostComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> sharePost(int id, {String channel = 'in_app'}) async {
    await _dio.post('/posts/$id/share', data: {'channel': channel});
  }
}

final feedRepositoryProvider = Provider<FeedRepository>((ref) => FeedRepository(ref.watch(dioProvider)));

/// The community feed (all post types) for the app-wide location — the same place Home's
/// "Community Discussions" names, so "See all" continues the list rather than widening it.
final feedProvider = FutureProvider<List<PostItem>>((ref) {
  ref.bindToAccount();
  final s = ref.watch(homeScopeProvider);
  return ref.watch(feedRepositoryProvider).posts(scope: s.scope, areaId: s.overrideAreaId);
});

/// A single post with its comments, keyed by post id.
final postDetailProvider = FutureProvider.family<PostItem, int>((ref, id) {
  ref.bindToAccount();
  return ref.watch(feedRepositoryProvider).post(id);
});
