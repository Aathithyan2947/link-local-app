import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../discovery/data/block_overrides.dart';
import '../../discovery/presentation/block_action.dart';
import '../data/message_models.dart';
import '../../../core/navigation/push_guard.dart';
import '../../feed/data/post_models.dart' show postTypeLabels;
import '../../feed/presentation/post_detail_screen.dart';
import '../../discovery/presentation/widgets/discover_cards.dart' show NetworkThumb;
import '../../home/presentation/widgets/home_widgets.dart';
import '../data/messages_repository.dart';

/// One-to-one chat — the "Private Message" frame. Supports a starter message
/// (e.g. an enquiry from a listing) via [starter].
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherName,
    this.otherPhoto,
    this.messageType,
    this.entityType,
    this.entityId,
  });
  final int otherUserId;
  final String otherName;
  final String? otherPhoto;
  final String? messageType; // 'enquiry' for the first message
  final String? entityType;
  final int? entityId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Loading the thread marks it read on the server, so refresh the unread counts (the
    // conversation list, Home's badge, the profile's Messages count) once it's here — however
    // the chat was opened.
    ref.listenManual(threadProvider(widget.otherUserId), (_, next) {
      if (!next.hasValue) return;
      Future.microtask(() {
        if (!mounted) return;
        ref
          ..invalidate(conversationsProvider)
          ..invalidate(unreadCountProvider);
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(messagesRepositoryProvider).send(
            receiverId: widget.otherUserId,
            content: text,
            messageType: widget.messageType,
            entityType: widget.entityType,
            entityId: widget.entityId,
          );
      if (!mounted) return;
      _input.clear();
      ref.invalidate(threadProvider(widget.otherUserId));
      ref.invalidate(conversationsProvider);
      await ref.read(threadProvider(widget.otherUserId).future);
    } on DioException catch (e) {
      if (!mounted) return;
      final err = ApiException.fromDio(e);
      // 403: a block happened while the chat was open — say so and switch to the blocked bar.
      if (err.statusCode == 403) refreshChatAfterBlock(ref, widget.otherUserId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.statusCode == 403 ? err.message : 'Could not send')),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meId = ref.watch(authControllerProvider).user?.id;
    final async = ref.watch(threadProvider(widget.otherUserId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Avatar(name: widget.otherName, photoUrl: widget.otherPhoto, radius: 16),
            const SizedBox(width: 10),
            Text(widget.otherName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(
                  child: OutlinedButton(onPressed: () => ref.invalidate(threadProvider(widget.otherUserId)), child: const Text('Retry'))),
              data: (thread) {
                if (thread.messages.isEmpty) {
                  return const Center(child: Text('Say hello 👋', style: TextStyle(color: AppColors.textMuted)));
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: thread.messages.length,
                  itemBuilder: (_, i) {
                    final m = thread.messages[i];
                    final mine = m.senderId == meId;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                        decoration: BoxDecoration(
                          color: mine ? AppColors.primary : AppColors.surface,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(14),
                            topRight: const Radius.circular(14),
                            bottomLeft: Radius.circular(mine ? 14 : 2),
                            bottomRight: Radius.circular(mine ? 2 : 14),
                          ),
                          border: mine ? null : Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // A shared post: the sender's note (if they wrote one) over a
                            // preview of the post that opens it.
                            if (!m.isSharedPost || m.content != 'Shared a post')
                              Text(m.content,
                                  style: TextStyle(color: mine ? Colors.white : AppColors.textPrimary, fontSize: 14)),
                            if (m.isSharedPost) ...[
                              if (m.content != 'Shared a post') const SizedBox(height: 8),
                              SharedPostBubble(postId: m.entityId!, post: m.post),
                            ],
                            if (m.createdAt != null) ...[
                              const SizedBox(height: 2),
                              Text(DateFormat('h:mm a').format(m.createdAt!),
                                  style: TextStyle(
                                      color: mine ? Colors.white70 : AppColors.textMuted, fontSize: 10)),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          switch (async.value) {
            final ChatThread t when _blockedByMe(t) || t.blockedByThem =>
              _BlockedBar(thread: t, name: widget.otherName, byMe: _blockedByMe(t)),
            _ => _composer(),
          },
        ],
      ),
    );
  }

  /// This session's block / unblock wins over the (possibly older) thread from the server.
  bool _blockedByMe(ChatThread t) => isBlockedNow(ref, t.otherId, fromServer: t.blockedByMe);

  Widget _composer() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Message…', isDense: true, border: InputBorder.none),
                ),
              ),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: AppColors.primary),
              ),
            ],
          ),
        ),
      );
}

/// Takes the composer's place when either side has blocked the other. The member who blocked
/// can unblock here; the blocked side only learns they can't reply.
class _BlockedBar extends ConsumerStatefulWidget {
  const _BlockedBar({required this.thread, required this.name, required this.byMe});
  final ChatThread thread;
  final String name;
  final bool byMe;

  @override
  ConsumerState<_BlockedBar> createState() => _BlockedBarState();
}

class _BlockedBarState extends ConsumerState<_BlockedBar> {
  Future<void> _unblock() =>
      setBlocked(context, userId: widget.thread.otherId, name: widget.name, block: false);

  @override
  Widget build(BuildContext context) {
    final byMe = widget.byMe;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            const Icon(Icons.block, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                byMe ? 'You blocked ${widget.name}.' : "You can't reply to this conversation.",
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            if (byMe)
              TextButton(
                onPressed: _unblock,
                child: const Text('Unblock', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}

/// A post shared into the chat: author, type, a few lines and the photo. Tapping opens the post
/// (likes and comments there). A post the author has since removed says so instead.
class SharedPostBubble extends StatelessWidget {
  const SharedPostBubble({super.key, required this.postId, required this.post});
  final int postId;
  final SharedPostPreview? post;

  @override
  Widget build(BuildContext context) {
    final p = post;
    if (p == null || !p.isActive) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text('This post is no longer available',
            style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.textMuted)),
      );
    }
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.pushPage(MaterialPageRoute(builder: (_) => PostDetailScreen(id: postId))),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.photoUrl != null)
                NetworkThumb(
                  photoUrl: p.photoUrl,
                  fallbackIcon: Icons.image_outlined,
                  width: double.infinity,
                  height: 130,
                  radius: BorderRadius.zero,
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Avatar(name: p.authorName, photoUrl: p.authorPhoto, radius: 12),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(p.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.ink)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(postTypeLabels[p.postType] ?? 'Update',
                              style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    if (p.text.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(p.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    ],
                    const SizedBox(height: 6),
                    const Text('View post',
                        style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
