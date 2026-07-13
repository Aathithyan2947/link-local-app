import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../data/messages_repository.dart';
import 'chat_screen.dart';

/// The user's conversation list — tap a row to open the chat.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conversationsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Messages')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: OutlinedButton(onPressed: () => ref.invalidate(conversationsProvider), child: const Text('Retry'))),
        data: (convos) {
          if (convos.isEmpty) {
            return const Center(child: Text('No conversations yet.'));
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(conversationsProvider),
            child: ListView.separated(
              itemCount: convos.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 76, color: AppColors.border),
              itemBuilder: (_, i) {
                final c = convos[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
    );
  }
}
