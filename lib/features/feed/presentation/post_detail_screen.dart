import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/push_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../discovery/presentation/group_profile_screen.dart';
import '../data/feed_repository.dart';
import 'widgets/comments_panel.dart';
import 'widgets/post_card.dart';

/// A single post above its comment thread — the same [CommentsPanel] the discussion cards
/// open as a sheet, so liking, replying and sorting work identically in both places. A group
/// post viewed by a non-member is read-only, with a way to the group to join.
class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(postDetailProvider(id));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Post')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: OutlinedButton(onPressed: () => ref.invalidate(postDetailProvider(id)), child: const Text('Retry')),
        ),
        data: (post) => CommentsPanel(
          postId: post.id,
          canInteract: post.canInteract,
          initialCount: post.comments,
          header: PostCard(post: post),
          onJoin: post.groupId == null
              ? null
              : () => context.pushPage(MaterialPageRoute(builder: (_) => GroupProfileScreen(id: post.groupId!))),
        ),
      ),
    );
  }
}
