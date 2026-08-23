import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../data/feed_repository.dart';
import '../data/post_models.dart';
import 'widgets/post_card.dart';

/// A single post with its comment thread and an inline composer.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(feedRepositoryProvider).addComment(widget.id, text);
      if (!mounted) return;
      _comment.clear();
      FocusScope.of(context).unfocus();
      ref.invalidate(postDetailProvider(widget.id));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post comment')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(postDetailProvider(widget.id));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Post')),
      body: Column(
        children: [
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(
                child: OutlinedButton(
                    onPressed: () => ref.invalidate(postDetailProvider(widget.id)), child: const Text('Retry')),
              ),
              data: (post) => RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => ref.refresh(postDetailProvider(widget.id).future),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    PostCard(post: post),
                    const SizedBox(height: 8),
                    Text('${post.comments} Comments',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 12),
                    if (post.commentList.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: Text('No comments yet.', style: TextStyle(color: AppColors.textMuted))),
                      )
                    else
                      ...post.commentList.map((c) => _CommentTile(comment: c)),
                  ],
                ),
              ),
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
                  controller: _comment,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Add a comment…',
                    isDense: true,
                    border: InputBorder.none,
                  ),
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

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final PostComment comment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(name: comment.authorName, photoUrl: comment.authorPhoto, radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(comment.authorName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(width: 8),
                      Text(relativeTime(comment.createdAt),
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ]),
                    const SizedBox(height: 2),
                    Text(comment.comment, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
          if (comment.replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 8),
              child: Column(children: comment.replies.map((r) => _CommentTile(comment: r)).toList()),
            ),
        ],
      ),
    );
  }
}
