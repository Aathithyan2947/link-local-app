import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../discovery/presentation/user_profile_screen.dart';
import '../../../home/presentation/widgets/home_widgets.dart';
import '../../data/feed_repository.dart';
import '../../data/post_models.dart';
import 'like_sync.dart';
import 'share_post_sheet.dart';
import '../../../../core/navigation/push_guard.dart';

/// A community post card: author + type chip · text · media · like/comment/share.
/// Manages its own like state optimistically so the whole feed needn't refresh.
class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.post, this.onOpen, this.onComment});
  final PostItem post;
  final VoidCallback? onOpen;
  final VoidCallback? onComment;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  late final LikeSync _like = LikeSync(
    liked: widget.post.liked,
    likes: widget.post.likes,
    send: (liked) => ref.read(feedRepositoryProvider).setLike(widget.post.id, liked),
    onChanged: () {
      if (mounted) setState(() {});
    },
    onError: (_) => _snack('Could not update like'),
  );
  late int _shares = widget.post.shares;
  bool _sharing = false;

  bool get _liked => _like.liked;
  int get _likes => _like.likes;

  @override
  void didUpdateWidget(PostCard old) {
    super.didUpdateWidget(old);
    if (old.post.likes != widget.post.likes || old.post.liked != widget.post.liked) {
      _like.reset(liked: widget.post.liked, likes: widget.post.likes);
    }
    if (old.post.shares != widget.post.shares) _shares = widget.post.shares;
  }

  @override
  void dispose() {
    _like.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // A group post is view-only for anyone outside the group: no like, comment or share.
  void _toggleLike() =>
      widget.post.canInteract ? _like.tap() : _snack('Join the group to like, comment or share');

  void _openAuthor() {
    final pid = widget.post.authorProfileId;
    if (pid == null) return;
    context.pushPage(MaterialPageRoute(builder: (_) => UserProfileScreen(id: pid)));
  }

  /// Opens "Send to" (share into LinkLocal chats); the count goes up once it's sent.
  Future<void> _share() async {
    if (!widget.post.canInteract) return _snack('Join the group to like, comment or share');
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final sent = await showSharePostSheet(context, postId: widget.post.id);
      if (sent && mounted) setState(() => _shares++);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _openAuthor,
                  child: Avatar(name: p.authorName, photoUrl: p.authorPhoto, radius: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _openAuthor,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.authorName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text('Resident · ${relativeTime(p.createdAt)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(20)),
                  child: Text(p.typeLabel,
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 11)),
                ),
              ],
            ),
          ),
          if (p.text?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: GestureDetector(
                onTap: widget.onOpen,
                child: Text(p.text!, style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary)),
              ),
            ),
          if (p.media.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: CachedNetworkImage(
                imageUrl: AppConfig.assetUrl(p.media.first.url),
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(height: 200, color: AppColors.primarySurface),
                errorWidget: (_, _, _) => Container(
                    height: 200, color: AppColors.primarySurface, child: const Icon(Icons.broken_image_outlined)),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                _action(_liked ? Icons.favorite : Icons.favorite_border, '$_likes',
                    color: _liked ? AppColors.error : AppColors.textSecondary, onTap: _toggleLike),
                _action(Icons.mode_comment_outlined, '${p.comments}', onTap: widget.onComment ?? widget.onOpen),
                _action(Icons.share_outlined, _shares > 0 ? '$_shares' : 'Share',
                    onTap: _sharing ? null : _share),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, {Color? color, VoidCallback? onTap}) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: color ?? AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 13, color: color ?? AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
}
