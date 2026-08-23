import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../data/message_models.dart';
import '../data/messages_repository.dart';
import 'chat_screen.dart';

/// The user's conversation list — tap a row to open the chat.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Conversation> _filter(List<Conversation> all) {
    if (_query.trim().isEmpty) return all;
    final q = _query.trim().toLowerCase();
    return all.where((c) => c.otherName.toLowerCase().contains(q) || c.lastMessage.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(conversationsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('LinkLocal', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text('Messages', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 2),
            const Text('Your Conversations', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
            const SizedBox(height: 16),
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                      textInputAction: TextInputAction.search,
                      cursorColor: AppColors.primary,
                      style: const TextStyle(fontSize: 15, color: AppColors.ink),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        hintText: 'Search conversations',
                        hintStyle: TextStyle(color: AppColors.textMuted),
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                error: (e, _) =>
                    Center(child: OutlinedButton(onPressed: () => ref.invalidate(conversationsProvider), child: const Text('Retry'))),
                data: (convos) {
                  final shown = _filter(convos);
                  if (convos.isEmpty) {
                    return const Center(child: Text('No conversations yet.'));
                  }
                  if (shown.isEmpty) {
                    return const Center(child: Text('No matches.'));
                  }
                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () => ref.refresh(conversationsProvider.future),
                    child: ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (_, i) {
                        final c = shown[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 6),
                          leading: Avatar(name: c.otherName, photoUrl: c.otherPhoto, radius: 24),
                          title: Text(c.otherName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(c.lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.unread > 0 ? AppColors.textPrimary : AppColors.textMuted)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (c.lastAt != null)
                                Text(DateFormat('h:mm a').format(c.lastAt!),
                                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              const SizedBox(height: 4),
                              if (c.unread > 0)
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                  child: Text('${c.unread}',
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                                ),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ChatScreen(otherUserId: c.otherId, otherName: c.otherName, otherPhoto: c.otherPhoto),
                            ));
                            ref.invalidate(conversationsProvider);
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
