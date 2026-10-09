import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../../discovery/data/blocked_user_models.dart';
import '../../discovery/data/block_overrides.dart';
import '../../discovery/discovery_repository.dart';
import '../../discovery/presentation/block_action.dart';

final _blockedUsersProvider = FutureProvider.autoDispose<List<BlockedUserItem>>(
  (ref) => ref.watch(discoveryRepositoryProvider).listBlockedUsers(),
);

/// The member's blocked-users list — each row can be unblocked. Matches the "Blocked Users" mockup.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  /// The row goes at once; their profiles and chat catch up in the background.
  Future<void> _unblock(BuildContext context, BlockedUserItem u) => setBlocked(
    context,
    userId: u.userId,
    name: u.name,
    block: false,
    refresh: [_blockedUsersProvider, serviceProviderDetailProvider, publicProfileProvider],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_blockedUsersProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Blocked Users'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ErrorBanner(message: e.toString()),
          ),
        ),
        data: (all) {
          final overrides = ref.watch(blockOverridesProvider);
          final items = all.where((u) => overrides[u.userId] != false).toList();
          if (items.isEmpty) {
            return const Center(child: Text('No blocked users.', style: TextStyle(color: AppColors.textSecondary)));
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => ref.refresh(_blockedUsersProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final u = items[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primarySurface,
                        backgroundImage: u.photoUrl != null ? NetworkImage(u.photoUrl!) : null,
                        child: u.photoUrl == null
                            ? Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                            const SizedBox(height: 2),
                            Text('${u.role}${u.location != null ? ' · ${u.location}' : ''}',
                                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _unblock(context, u),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
                          // The theme's buttons are full-width (Size.fromHeight); in a row that
                          // is an infinite width and the whole list failed to lay out (blank).
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: const Text('Unblock'),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
