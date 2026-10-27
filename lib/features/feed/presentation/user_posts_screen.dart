import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../address/presentation/address_proof_gate.dart';

import '../../../core/navigation/push_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../data/feed_repository.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import 'widgets/post_card.dart';

/// Everything one member has posted — where a profile's Posts "View More" leads, and (with
/// [mine]) Profile → My Posts. Same cards as the community feed (like, comment, open).
class UserPostsScreen extends ConsumerWidget {
  const UserPostsScreen({super.key, required this.userId, required this.name, this.mine = false});
  final int userId;
  final String name;

  /// The member's own posts: titled "My Posts", with a button to write one.
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userPostsProvider(userId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: mine
            ? const Text('My Posts')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Posts'),
                  Text('by $name', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ],
              ),
      ),
      // Creating a post refreshes this list (see invalidatePostLists).
      floatingActionButton: mine
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () =>
                  pushIfAddressProof(context, ref, action: 'create a post', page: (_) => const CreatePostScreen()),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Post'),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Couldn't load the posts"),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(userPostsProvider(userId)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(120, 44)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (posts) {
          if (posts.isEmpty) {
            return Center(child: Text(mine ? "You haven't posted yet." : 'No posts yet.'));
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => ref.refresh(userPostsProvider(userId).future),
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 16, 16, mine ? 90 : 32),
              itemCount: posts.length,
              itemBuilder: (context, i) {
                final p = posts[i];
                void open() async {
                  await context.pushPage(MaterialPageRoute(builder: (_) => PostDetailScreen(id: p.id)));
                  ref.invalidate(userPostsProvider(userId));
                }

                return PostCard(post: p, onOpen: open, onComment: open);
              },
            ),
          );
        },
      ),
    );
  }
}
