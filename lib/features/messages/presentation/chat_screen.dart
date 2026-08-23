import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
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
                            Text(m.content,
                                style: TextStyle(color: mine ? Colors.white : AppColors.textPrimary, fontSize: 14)),
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
          _composer(),
        ],
      ),
    );
  }

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
