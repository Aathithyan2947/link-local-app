import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/data/home_repository.dart';
import '../data/feed_repository.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import 'widgets/post_card.dart';
import '../../../core/navigation/push_guard.dart';

/// The community feed — full list of neighbourhood posts (from the Home
/// "Community Discussions" section). Like / comment / share / create.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(feedProvider);
    final place = locationLabel(ref.watch(homeScopeProvider), ref.watch(homeFeedProvider).asData?.value);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Community Feed'),
            Text('in $place', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
          await context.pushPage(MaterialPageRoute(builder: (_) => const CreatePostScreen()));
          ref.invalidate(feedProvider);
        },
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Post'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Couldn't load the feed"),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => ref.invalidate(feedProvider), child: const Text('Retry')),
            ],
          ),
        ),
        data: (posts) {
          if (posts.isEmpty) {
            return const Center(child: Text('No posts yet — be the first to share.'));
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => ref.refresh(feedProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: posts.length,
              itemBuilder: (context, i) {
                final p = posts[i];
                void open() async {
                  await context.pushPage(
                    MaterialPageRoute(builder: (_) => PostDetailScreen(id: p.id)),
                  );
                  ref.invalidate(feedProvider);
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
