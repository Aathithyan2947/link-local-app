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
  });
  final int otherId;
  final String otherName;
  final String? otherPhoto;
  final String lastMessage;
  final DateTime? lastAt;
  final int unread;

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final other = j['other'] as Map<String, dynamic>?;
    final profile = other?['profile'] as Map<String, dynamic>?;
    return Conversation(
      otherId: _asInt(other?['id']),
      otherName: profile?['name'] as String? ?? 'Member',
      otherPhoto: profile?['photoUrl'] as String?,
      lastMessage: j['lastMessage'] as String? ?? '',
      lastAt: j['lastAt'] != null ? DateTime.tryParse(j['lastAt'] as String) : null,
      unread: _asInt(j['unread']),
    );
  }
}

/// A single message in a thread.
class ChatMessage {
  const ChatMessage({required this.id, required this.senderId, required this.content, this.createdAt});
  final int id;
  final int senderId;
  final String content;
  final DateTime? createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: _asInt(j['id']),
        senderId: _asInt(j['senderId']),
        content: j['content'] as String? ?? '',
        createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'] as String) : null,
      );
}

/// A full chat thread with one other user.
class ChatThread {
  const ChatThread({required this.otherId, required this.otherName, this.otherPhoto, this.messages = const []});
  final int otherId;
  final String otherName;
  final String? otherPhoto;
  final List<ChatMessage> messages;

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
    );
  }
}
