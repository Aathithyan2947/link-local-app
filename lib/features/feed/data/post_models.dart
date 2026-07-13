int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

/// Post types → human labels for the type chip.
const postTypeLabels = <String, String>{
  'buy_sell': 'Buy / Sell',
  'ask_help': 'Ask for help',
  'offer_help': 'Offer help',
  'share_update': 'Update',
};

class PostMedia {
  const PostMedia({required this.mediaType, required this.url});
  final String mediaType;
  final String url;
  factory PostMedia.fromJson(Map<String, dynamic> j) =>
      PostMedia(mediaType: j['mediaType'] as String? ?? 'photo', url: j['url'] as String? ?? '');
}

class PostComment {
  const PostComment({
    required this.id,
    required this.comment,
    required this.authorName,
    this.authorPhoto,
    this.createdAt,
    this.replies = const [],
  });
  final int id;
  final String comment;
  final String authorName;
  final String? authorPhoto;
  final DateTime? createdAt;
  final List<PostComment> replies;

  factory PostComment.fromJson(Map<String, dynamic> j) {
    final profile = (j['user'] as Map<String, dynamic>?)?['profile'] as Map<String, dynamic>?;
    return PostComment(
      id: _asInt(j['id']),
      comment: j['comment'] as String? ?? '',
      authorName: profile?['name'] as String? ?? 'Neighbour',
      authorPhoto: profile?['photoUrl'] as String?,
      createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'] as String) : null,
      replies: ((j['replies'] as List?) ?? [])
          .map((e) => PostComment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PostItem {
  const PostItem({
    required this.id,
    required this.postType,
    this.text,
    required this.authorId,
    this.authorProfileId,
    required this.authorName,
    this.authorPhoto,
    this.media = const [],
    required this.likes,
    required this.comments,
    required this.shares,
    this.liked = false,
    this.createdAt,
    this.commentList = const [],
  });

  final int id;
  final String postType;
  final String? text;
  final int authorId;
  final int? authorProfileId;
  final String authorName;
  final String? authorPhoto;
  final List<PostMedia> media;
  final int likes;
  final int comments;
  final int shares;
  final bool liked;
  final DateTime? createdAt;
  final List<PostComment> commentList; // populated on detail only

  String get typeLabel => postTypeLabels[postType] ?? 'Update';

  PostItem copyWith({bool? liked, int? likes}) => PostItem(
        id: id,
        postType: postType,
        text: text,
        authorId: authorId,
        authorProfileId: authorProfileId,
        authorName: authorName,
        authorPhoto: authorPhoto,
        media: media,
        likes: likes ?? this.likes,
        comments: comments,
        shares: shares,
        liked: liked ?? this.liked,
        createdAt: createdAt,
        commentList: commentList,
      );

  factory PostItem.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>?;
    final profile = user?['profile'] as Map<String, dynamic>?;
    final count = j['_count'] as Map<String, dynamic>?;
    return PostItem(
      id: _asInt(j['id']),
      postType: j['postType'] as String? ?? 'share_update',
      text: j['textContent'] as String?,
      authorId: _asInt(user?['id']),
      authorProfileId: profile?['id'] != null ? _asInt(profile!['id']) : null,
      authorName: profile?['name'] as String? ?? 'Neighbour',
      authorPhoto: profile?['photoUrl'] as String?,
      media: ((j['media'] as List?) ?? [])
          .map((e) => PostMedia.fromJson(e as Map<String, dynamic>))
          .toList(),
      likes: _asInt(count?['likes']),
      comments: _asInt(count?['comments']),
      shares: _asInt(count?['shares']),
      liked: j['viewerLiked'] as bool? ?? false,
      createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'] as String) : null,
      commentList: ((j['comments'] as List?) ?? [])
          .map((e) => PostComment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Short relative time, e.g. `2hr ago`, `5m ago`, `Just now`.
String relativeTime(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}hr ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${(d.inDays / 7).floor()}w ago';
}
