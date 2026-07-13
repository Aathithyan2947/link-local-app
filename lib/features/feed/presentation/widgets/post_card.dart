import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../discovery/presentation/user_profile_screen.dart';
import '../../../home/presentation/widgets/home_widgets.dart';
import '../../data/feed_repository.dart';
import '../../data/post_models.dart';

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
  late bool _liked = widget.post.liked;
  late int _likes = widget.post.likes;
  bool _sharing = false;

  Future<void> _toggleLike() async {
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
    });
    try {
      final liked = await ref.read(feedRepositoryProvider).toggleLike(widget.post.id);
      if (mounted && liked != _liked) setState(() => _liked = liked);
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = !_liked;
          _likes += _liked ? 1 : -1;
        });
      }
    }
  }

  void _openAuthor() {
    final pid = widget.post.authorProfileId;
    if (pid == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(id: pid)));
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await ref.read(feedRepositoryProvider).sharePost(widget.post.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shared')));
    } catch (_) {
      // ignore
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
                _action(Icons.share_outlined, p.shares > 0 ? '${p.shares}' : 'Share',
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
