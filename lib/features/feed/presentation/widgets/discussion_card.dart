import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../address/presentation/address_proof_gate.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../home/data/home_models.dart';
import '../../../home/presentation/widgets/home_widgets.dart';
import '../../data/feed_repository.dart';
import '../../data/post_models.dart';
import 'comments_panel.dart';
import 'like_sync.dart';
import 'share_post_sheet.dart';

/// A discussion post as a card you can act on directly — Home and group pages share it.
///
/// The heart likes at once (see [LikeSync]); the comment button or the top-comment preview
/// opens the comments sheet; share records a share. On a group post the viewer isn't a
/// member of, the card is read-only and those actions explain how to join instead.
class DiscussionCard extends ConsumerStatefulWidget {
  const DiscussionCard({
    super.key,
    required this.item,
    this.onOpen,
    this.onJoin,
    this.onChanged,
    this.showGroup = false,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final DiscussionItem item;

  /// Opens the full post (the card body).
  final VoidCallback? onOpen;

  /// Offered to a non-member of the post's group.
  final VoidCallback? onJoin;

  /// The card changed something the parent list may want to refetch (comment preview).
  final VoidCallback? onChanged;

  /// Names the post's group under the author (for mixed lists like Home).
  final bool showGroup;
  final EdgeInsetsGeometry margin;

  @override
  ConsumerState<DiscussionCard> createState() => _DiscussionCardState();
}

class _DiscussionCardState extends ConsumerState<DiscussionCard> {
  late final LikeSync _like = LikeSync(
    liked: widget.item.liked,
    likes: widget.item.likes,
    send: (liked) => ref.read(feedRepositoryProvider).setLike(widget.item.id, liked),
    onChanged: () {
      if (mounted) setState(() {});
    },
    onError: (e) {
      if (mounted && !handleAddressProofError(context, e, action: 'like a post')) _snack('Could not update like');
    },
  );
  late int _comments = widget.item.comments;
  late int _shares = widget.item.shares;
  bool _sharing = false;

  DiscussionItem get _item => widget.item;

  @override
  void didUpdateWidget(DiscussionCard old) {
    super.didUpdateWidget(old);
    if (old.item.likes != _item.likes || old.item.liked != _item.liked) {
      _like.reset(liked: _item.liked, likes: _item.likes);
    }
    if (old.item.comments != _item.comments) _comments = _item.comments;
    if (old.item.shares != _item.shares) _shares = _item.shares;
  }

  @override
  void dispose() {
    _like.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool offerJoin = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          action: offerJoin && widget.onJoin != null ? SnackBarAction(label: 'Join', onPressed: widget.onJoin!) : null,
        ),
      );
  }

  void _needsJoin() => _snack('Join the group to like, comment or share', offerJoin: true);

  void _tapLike() {
    if (!_item.canInteract) return _needsJoin();
    // Liking needs an address proof (BUG-084).
    if (checkAddressProofNow(context, ref, action: 'like a post')) _like.tap();
  }

  Future<void> _openComments({bool focusComposer = false}) async {
    final count = await showCommentsSheet(
      context,
      postId: _item.id,
      canInteract: _item.canInteract,
      initialCount: _comments,
      focusComposer: focusComposer && _item.canInteract,
      onJoin: widget.onJoin,
    );
    if (!mounted || count == null) return;
    if (count != _comments) {
      setState(() => _comments = count);
      widget.onChanged?.call(); // the top-comment preview may have changed
    }
  }

  /// Opens "Send to" (share into LinkLocal chats); the count goes up once it's sent.
  Future<void> _share() async {
    if (!_item.canInteract) return _needsJoin();
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final sent = await showSharePostSheet(context, postId: _item.id);
      if (sent && mounted) setState(() => _shares++);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (widget.showGroup && _item.groupTitle != null) 'in ${_item.groupTitle}',
      relativeTime(_item.createdAt),
    ].where((s) => s.isNotEmpty).join('  •  ');

    return Padding(
      padding: widget.margin,
      // Material (not a decorated Container) so ripples show on the card's own surface.
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: widget.onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Avatar(name: _item.authorName, photoUrl: _item.authorPhoto, radius: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _item.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                  color: AppColors.ink,
                                ),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_item.text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      // A preview: the card opens the post, which shows it all.
                      Text(
                        _item.text,
                        maxLines: kPostPreviewLines,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _commentPreview(),
            const Divider(height: 1, color: AppColors.border),
            _actions(),
          ],
        ),
      ),
    );
  }

  /// YouTube's comments teaser: the top comment, or a prompt to start one.
  Widget _commentPreview() {
    final top = _item.topComment;
    if (top == null && !_item.canInteract) return const SizedBox(height: 4);
    return InkWell(
      onTap: () => _openComments(focusComposer: top == null),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
          child: top == null
              ? const Row(
                  children: [
                    Icon(Icons.mode_comment_outlined, size: 16, color: AppColors.textMuted),
                    SizedBox(width: 8),
                    Text('Add a comment…', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Comments',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                          ),
                          TextSpan(
                            text: '  $_comments',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Avatar(name: top.authorName, photoUrl: top.authorPhoto, radius: 11),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            top.comment,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _actions() {
    const label = TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600);
    final locked = !_item.canInteract;
    return Row(
      children: [
        _action(
          onTap: _tapLike,
          semantic: _like.liked ? 'Unlike' : 'Like',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _like.liked ? Icons.favorite : Icons.favorite_border,
                size: 19,
                color: _like.liked ? AppColors.error : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text('${_like.likes}', style: label),
            ],
          ),
        ),
        _action(
          onTap: _openComments,
          semantic: 'Comments',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mode_comment_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('$_comments', style: label),
            ],
          ),
        ),
        _action(
          onTap: _share,
          semantic: 'Share',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sharing
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.share_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(_shares > 0 ? '$_shares' : 'Share', style: label),
            ],
          ),
        ),
        const Spacer(),
        if (locked)
          const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
          ),
      ],
    );
  }

  Widget _action({required Widget child, required VoidCallback onTap, required String semantic}) => Semantics(
    button: true,
    label: semantic,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(widthFactor: 1, child: child),
        ),
      ),
    ),
  );
}
