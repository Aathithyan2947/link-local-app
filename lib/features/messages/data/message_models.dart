import '../../../core/time/server_time.dart';

int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

/// One row in the conversation list.
class Conversation {
  const Conversation({
    required this.otherId,
    required this.otherName,
    this.otherPhoto,
    required this.lastMessage,
    this.lastAt,
    this.unread = 0,
    this.blockedByMe = false,
  });
  final int otherId;
  final String otherName;
  final String? otherPhoto;
  final String lastMessage;
  final DateTime? lastAt;
  final int unread;
  /// The member blocked this person: the history stays, the row is marked.
  final bool blockedByMe;

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final other = j['other'] as Map<String, dynamic>?;
    final profile = other?['profile'] as Map<String, dynamic>?;
    return Conversation(
      otherId: _asInt(other?['id']),
      otherName: profile?['name'] as String? ?? 'Member',
      otherPhoto: profile?['photoUrl'] as String?,
      lastMessage: j['lastMessage'] as String? ?? '',
      lastAt: parseServerTime(j['lastAt']),
      unread: _asInt(j['unread']),
      blockedByMe: j['blockedByMe'] == true,
    );
  }
}

/// A single message in a thread.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    this.createdAt,
    this.entityType,
    this.entityId,
    this.post,
  });
  final int id;
  final int senderId;
  final String content;
  final DateTime? createdAt;

  /// What the message is about, if anything — e.g. `post` when a post was shared.
  final String? entityType;
  final int? entityId;

  /// The shared post, as the chat shows it (null if it no longer exists).
  final SharedPostPreview? post;

  bool get isSharedPost => entityType == 'post' && entityId != null;

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final post = j['post'];
    return ChatMessage(
      id: _asInt(j['id']),
      senderId: _asInt(j['senderId']),
      content: j['content'] as String? ?? '',
      createdAt: parseServerTime(j['createdAt']),
      entityType: j['entityType'] as String?,
      entityId: j['entityId'] == null ? null : _asInt(j['entityId']),
      post: post is Map<String, dynamic> ? SharedPostPreview.fromJson(post) : null,
    );
  }
}

/// What a chat shows of a shared post: its author, text and first photo.
class SharedPostPreview {
  const SharedPostPreview({
    required this.id,
    required this.postType,
    required this.text,
    required this.authorName,
    this.authorPhoto,
    this.photoUrl,
    this.isActive = true,
  });
  final int id;
  final String postType;
  final String text;
  final String authorName;
  final String? authorPhoto;
  final String? photoUrl;

  /// False once the author has removed it.
  final bool isActive;

  factory SharedPostPreview.fromJson(Map<String, dynamic> j) => SharedPostPreview(
        id: _asInt(j['id']),
        postType: j['postType'] as String? ?? 'share_update',
        text: j['text'] as String? ?? '',
        authorName: j['authorName'] as String? ?? 'Member',
        authorPhoto: j['authorPhoto'] as String?,
        photoUrl: j['photoUrl'] as String?,
        isActive: j['isActive'] != false,
      );
}

/// A full chat thread with one other user.
class ChatThread {
  const ChatThread({
    required this.otherId,
    required this.otherName,
    this.otherPhoto,
    this.messages = const [],
    this.blockedByMe = false,
    this.blockedByThem = false,
  });
  final int otherId;
  final String otherName;
  final String? otherPhoto;
  final List<ChatMessage> messages;

  /// Either side blocking stops messaging both ways; the history stays readable.
  final bool blockedByMe;
  final bool blockedByThem;
  bool get canMessage => !blockedByMe && !blockedByThem;

  factory ChatThread.fromJson(Map<String, dynamic> j) {
    final other = j['other'] as Map<String, dynamic>?;
    final profile = other?['profile'] as Map<String, dynamic>?;
    return ChatThread(
      otherId: _asInt(other?['id']),
      otherName: profile?['name'] as String? ?? 'Member',
      otherPhoto: profile?['photoUrl'] as String?,
      messages: ((j['messages'] as List?) ?? [])
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      blockedByMe: j['blockedByMe'] == true,
      blockedByThem: j['blockedByThem'] == true,
    );
  }
}
