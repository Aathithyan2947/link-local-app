import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../discovery/data/block_overrides.dart';
import '../../../home/presentation/widgets/home_widgets.dart';
import '../../../messages/data/message_models.dart';
import '../../../messages/data/messages_repository.dart';
import '../../data/feed_repository.dart';

/// Share a post into LinkLocal chats: pick people you've talked to, add an optional note, send.
/// Each gets a chat message pointing at the post, which their chat shows as a preview that opens
/// it. Says how it went, and records one share if it reached anyone.
///
/// Returns true when it was sent to at least one person (the caller bumps its share count).
Future<bool> showSharePostSheet(BuildContext context, {required int postId}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SharePostSheet(postId: postId),
  );
  return sent ?? false;
}

class SharePostSheet extends ConsumerStatefulWidget {
  const SharePostSheet({super.key, required this.postId});
  final int postId;

  @override
  ConsumerState<SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends ConsumerState<SharePostSheet> {
  final _search = TextEditingController();
  final _note = TextEditingController();
  final _picked = <int, String>{}; // user id → name, in the order picked
  bool _sending = false;

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  void _toggle(Conversation c) => setState(() {
        if (_picked.remove(c.otherId) == null) _picked[c.otherId] = c.otherName;
      });

  Future<void> _send() async {
    if (_picked.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final messages = ref.read(messagesRepositoryProvider);
    final note = _note.text.trim();
    final sentTo = <String>[];
    final failed = <String, String>{}; // name → reason

    for (final MapEntry(key: id, value: name) in _picked.entries) {
      try {
        await messages.send(
          receiverId: id,
          content: note.isEmpty ? 'Shared a post' : note,
          messageType: 'direct',
          entityType: 'post',
          entityId: widget.postId,
        );
        sentTo.add(name);
        ref.invalidate(threadProvider(id));
      } on DioException catch (e) {
        final err = ApiException.fromDio(e);
        failed[name] = err.statusCode == 403 || err.statusCode == 404 ? err.message : 'Something went wrong';
      } catch (_) {
        failed[name] = 'Something went wrong';
      }
    }

    if (sentTo.isNotEmpty) {
      ref.invalidate(conversationsProvider);
      try {
        await ref.read(feedRepositoryProvider).sharePost(widget.postId);
      } catch (_) {
        // The messages went out; only the share count missed this one.
      }
    }

    final parts = <String>[
      if (sentTo.length == 1) 'Sent to ${sentTo.single}',
      if (sentTo.length > 1) 'Sent to ${sentTo.length} people',
      for (final MapEntry(key: name, value: why) in failed.entries) "Couldn't send to $name: $why",
    ];
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          sentTo.isEmpty && failed.values.every((why) => why == 'Something went wrong')
              ? 'Could not share'
              : parts.join('\n'),
        ),
      ));
    if (!mounted) return;
    if (sentTo.isEmpty) {
      setState(() => _sending = false); // stay open so they can pick someone else
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(conversationsProvider);
    final q = _search.text.trim().toLowerCase();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Text('Send to', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                error: (e, _) => Center(
                  child: TextButton(
                    onPressed: () => ref.invalidate(conversationsProvider),
                    child: const Text("Couldn't load your chats — retry"),
                  ),
                ),
                data: (all) {
                  if (all.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          "No conversations yet — start a chat from someone's profile to share with them.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }
                  final shown = q.isEmpty ? all : all.where((c) => c.otherName.toLowerCase().contains(q)).toList();
                  if (shown.isEmpty) return const Center(child: Text('No matches.'));
                  return ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) => _row(shown[i]),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _note,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Add a message (optional)', isDense: true),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _picked.isEmpty || _sending ? null : _send,
                    child: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_picked.length > 1 ? 'Send to ${_picked.length}' : 'Send'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Conversation c) {
    final blocked = isBlockedNow(ref, c.otherId, fromServer: c.blockedByMe);
    final picked = _picked.containsKey(c.otherId);
    return ListTile(
      enabled: !blocked,
      onTap: blocked ? null : () => _toggle(c),
      leading: Avatar(name: c.otherName, photoUrl: c.otherPhoto, radius: 20),
      title: Text(c.otherName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: blocked ? const Text('Blocked') : null,
      trailing: blocked
          ? null
          : Icon(
              picked ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              color: picked ? AppColors.primary : AppColors.textMuted,
            ),
    );
  }
}
