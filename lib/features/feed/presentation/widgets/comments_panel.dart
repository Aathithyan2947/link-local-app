import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../address/presentation/address_proof_gate.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../home/presentation/widgets/home_widgets.dart';
import '../../data/feed_repository.dart';
import '../../data/post_models.dart';
import 'like_sync.dart';

/// Opens a post's comments as a YouTube-style sheet over the current screen. Resolves to the
/// post's comment count when closed, so the card that opened it can update its own.
Future<int?> showCommentsSheet(
  BuildContext context, {
  required int postId,
  required bool canInteract,
  int initialCount = 0,
  bool focusComposer = false,
  VoidCallback? onJoin,
}) {
  var count = initialCount;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scroll) => Padding(
        // Lift the composer above the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: CommentsPanel(
          postId: postId,
          canInteract: canInteract,
          initialCount: initialCount,
          scrollController: scroll,
          autofocus: focusComposer,
          showSheetChrome: true,
          onCountChanged: (n) => count = n,
          onClose: () => Navigator.of(sheetContext).pop(count),
          onJoin: onJoin == null
              ? null
              : () {
                  Navigator.of(sheetContext).pop(count);
                  onJoin();
                },
        ),
      ),
    ),
  ).then((v) => v ?? count);
}

/// A post's comment thread: sort (Top / Newest), paged top-level comments, each with Like and
/// Reply and an expandable "N replies" thread, and a composer pinned at the bottom. Read-only
/// for someone who can't interact (a non-member on a group post), with a join prompt instead.
class CommentsPanel extends ConsumerStatefulWidget {
  const CommentsPanel({
    super.key,
    required this.postId,
    required this.canInteract,
    this.initialCount = 0,
    this.scrollController,
    this.header,
    this.autofocus = false,
    this.showSheetChrome = false,
    this.onCountChanged,
    this.onClose,
    this.onJoin,
  });

  final int postId;
  final bool canInteract;
  final int initialCount;
  final ScrollController? scrollController;

  /// Shown above the comments inside the scroll view (the post page puts the post here).
  final Widget? header;
  final bool autofocus;

  /// Drag handle and close button, for the bottom sheet.
  final bool showSheetChrome;
  final ValueChanged<int>? onCountChanged;
  final VoidCallback? onClose;
  final VoidCallback? onJoin;

  @override
  ConsumerState<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends ConsumerState<CommentsPanel> {
  static const _pageSize = 20;

  final _composer = TextEditingController();
  final _focus = FocusNode();

  String _sort = 'top';
  final _items = <PostComment>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadFailed = false;
  late int _total = widget.initialCount;
  late bool _canInteract = widget.canInteract;

  /// Bumped on every reload so a slow page from a previous sort can't land in the new list.
  int _generation = 0;

  /// Loaded replies per expanded thread; a thread absent here is collapsed.
  final _replies = <int, List<PostComment>>{};
  final _loadingReplies = <int>{};

  PostComment? _replyTo;
  bool _sending = false;

  FeedRepository get _repo => ref.read(feedRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _loadMore();
    // Not when the proof is known to be missing: the box is read-only then (BUG-084).
    if (widget.autofocus && widget.canInteract) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !addressProofKnownMissing(ref)) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _reload(String sort) async {
    setState(() {
      _sort = sort;
      _items.clear();
      _replies.clear();
      _page = 0;
      _hasMore = true;
      _generation++;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final gen = _generation;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final page = await _repo.comments(widget.postId, sort: _sort, page: _page + 1, pageSize: _pageSize);
      if (!mounted || gen != _generation) return;
      setState(() {
        _page++;
        // A comment posted this session may reappear in a later page; keep one copy.
        final seen = _items.map((c) => c.id).toSet();
        _items.addAll(page.items.where((c) => !seen.contains(c.id)));
        _hasMore = page.hasMore;
        _total = page.totalComments;
        _canInteract = page.canInteract;
      });
      widget.onCountChanged?.call(_total);
    } catch (_) {
      if (mounted && gen == _generation) setState(() => _loadFailed = true);
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _toggleReplies(PostComment c) async {
    if (_replies.containsKey(c.id)) {
      setState(() => _replies.remove(c.id));
      return;
    }
    await _loadReplies(c.id);
  }

  Future<void> _loadReplies(int threadId) async {
    setState(() => _loadingReplies.add(threadId));
    try {
      final list = await _repo.replies(threadId);
      if (mounted) setState(() => _replies[threadId] = list);
    } catch (_) {
      if (mounted) _snack('Could not load replies');
    } finally {
      if (mounted) setState(() => _loadingReplies.remove(threadId));
    }
  }

  void _startReply(PostComment c) {
    if (!checkAddressProofNow(context, ref, action: 'comment on a post')) return;
    setState(() => _replyTo = c);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    // Commenting needs an address proof (BUG-084); the text stays in the box meanwhile.
    if (!await ensureAddressProof(context, ref, action: 'comment on a post')) return;
    if (!mounted) return;
    final replyTo = _replyTo;
    // Replies are one level deep: replying to a reply joins its top-level thread.
    final threadId = replyTo == null ? null : (replyTo.parentId ?? replyTo.id);
    setState(() => _sending = true);
    try {
      final created = await _repo.addComment(widget.postId, text, parentCommentId: replyTo?.id);
      if (!mounted) return;
      _composer.clear();
      setState(() {
        _replyTo = null;
        _total++;
        if (threadId == null) {
          _items.insert(0, created);
        } else {
          final i = _items.indexWhere((c) => c.id == threadId);
          if (i >= 0) _items[i] = _items[i].copyWith(replyCount: _items[i].replyCount + 1);
          final loaded = _replies[threadId];
          if (loaded != null) loaded.add(created);
        }
      });
      widget.onCountChanged?.call(_total);
      // Show the reply in its thread, opening the thread if it was collapsed.
      if (threadId != null && !_replies.containsKey(threadId)) await _loadReplies(threadId);
    } catch (e) {
      if (!mounted || handleAddressProofError(context, e, action: 'comment on a post')) return;
      _snack(replyTo != null ? 'Could not post reply' : 'Could not post comment');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showSheetChrome) _sheetHeader(),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            // Load the next page a little before the end is reached.
            onNotification: (n) {
              if (n.metrics.extentAfter < 300) _loadMore();
              return false;
            },
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (widget.header != null) ...[widget.header!, const SizedBox(height: 8)],
                if (!widget.showSheetChrome) _titleRow(),
                ..._items.map(_thread),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  )
                else if (_loadFailed)
                  Center(
                    child: TextButton(onPressed: _loadMore, child: const Text('Could not load comments — retry')),
                  )
                else if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        _canInteract ? 'No comments yet. Start the conversation.' : 'No comments yet.',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _canInteract ? _composerBar() : _joinBar(),
      ],
    );
  }

  Widget _sheetHeader() => Column(
    children: [
      const SizedBox(height: 8),
      Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
        child: Row(
          children: [
            Expanded(child: _titleText()),
            IconButton(
              tooltip: 'Close',
              onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4), child: _sortChips()),
      const Divider(height: 1, color: AppColors.border),
    ],
  );

  Widget _titleRow() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(child: _titleText()),
        _sortChips(),
      ],
    ),
  );

  Widget _titleText() => Text.rich(
    TextSpan(
      children: [
        const TextSpan(text: 'Comments'),
        TextSpan(
          text: '  $_total',
          style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
        ),
      ],
    ),
    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink),
  );

  Widget _sortChips() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (value, label) in const [('top', 'Top'), ('newest', 'Newest')])
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _sort == value,
            onSelected: (_) => _sort == value ? null : _reload(value),
            visualDensity: VisualDensity.compact,
            selectedColor: AppColors.primarySurface,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _sort == value ? AppColors.primary : AppColors.textSecondary,
            ),
            side: BorderSide(color: _sort == value ? AppColors.primary : AppColors.border),
            showCheckmark: false,
          ),
        ),
    ],
  );

  /// A top-level comment with its expandable replies.
  Widget _thread(PostComment c) {
    final replies = _replies[c.id];
    final expanded = replies != null;
    return Padding(
      key: ValueKey('thread-${c.id}'),
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommentRow(comment: c, canInteract: _canInteract, onReply: _startReply),
          if (c.replyCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: TextButton.icon(
                onPressed: _loadingReplies.contains(c.id) ? null : () => _toggleReplies(c),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: _loadingReplies.contains(c.id)
                    ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20),
                label: Text(
                  expanded ? 'Hide replies' : '${c.replyCount} ${c.replyCount == 1 ? 'reply' : 'replies'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Column(
                children: replies
                    .map(
                      (r) => Padding(
                        key: ValueKey('reply-${r.id}'),
                        padding: const EdgeInsets.only(top: 8),
                        child: CommentRow(comment: r, canInteract: _canInteract, onReply: _startReply, small: true),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _composerBar() => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            Row(
              children: [
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Replying to @${_replyTo!.authorName}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Cancel reply',
                  onPressed: () => setState(() => _replyTo = null),
                  icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _composer,
                  focusNode: _focus,
                  // Without an address proof the box doesn't open the keyboard, and a tap says
                  // why before anything is typed (BUG-084).
                  readOnly: watchAddressProofMissing(ref),
                  onTap: () {
                    if (addressProofKnownMissing(ref)) {
                      showAddressProofRequired(context, action: 'comment on a post');
                    }
                  },
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: _replyTo != null ? 'Add a reply…' : 'Add a comment…',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Send',
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _joinBar() => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Join the group to like and comment',
              style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
            ),
          ),
          if (widget.onJoin != null) TextButton(onPressed: widget.onJoin, child: const Text('Join')),
        ],
      ),
    ),
  );
}

/// One comment or reply: avatar, name · time, text, and its Like / Reply actions.
class CommentRow extends ConsumerStatefulWidget {
  const CommentRow({
    super.key,
    required this.comment,
    required this.canInteract,
    required this.onReply,
    this.small = false,
  });
  final PostComment comment;
  final bool canInteract;
  final ValueChanged<PostComment> onReply;
  final bool small;

  @override
  ConsumerState<CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends ConsumerState<CommentRow> {
  late final LikeSync _like = LikeSync(
    liked: widget.comment.liked,
    likes: widget.comment.likes,
    send: (liked) => ref.read(feedRepositoryProvider).setCommentLike(widget.comment.id, liked),
    onChanged: () {
      if (mounted) setState(() {});
    },
    onError: (e) {
      if (!mounted || handleAddressProofError(context, e, action: 'like a comment')) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update like')));
    },
  );

  /// Liking needs an address proof (BUG-084).
  void _tapLike() {
    if (checkAddressProofNow(context, ref, action: 'like a comment')) _like.tap();
  }

  @override
  void didUpdateWidget(CommentRow old) {
    super.didUpdateWidget(old);
    if (old.comment.likes != widget.comment.likes || old.comment.liked != widget.comment.liked) {
      _like.reset(liked: widget.comment.liked, likes: widget.comment.likes);
    }
  }

  @override
  void dispose() {
    _like.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    const muted = TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Avatar(name: c.authorName, photoUrl: c.authorPhoto, radius: widget.small ? 12 : 15),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: c.authorName,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                    TextSpan(
                      text: '  ${relativeTime(c.createdAt)}',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 2),
              Text(c.comment, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.3)),
              Row(
                children: [
                  _ActionButton(
                    onTap: widget.canInteract ? _tapLike : null,
                    semanticLabel: _like.liked ? 'Unlike comment' : 'Like comment',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _like.liked ? Icons.favorite : Icons.favorite_border,
                          size: 16,
                          color: _like.liked ? AppColors.error : AppColors.textSecondary,
                        ),
                        if (_like.likes > 0) ...[const SizedBox(width: 4), Text('${_like.likes}', style: muted)],
                      ],
                    ),
                  ),
                  if (widget.canInteract)
                    _ActionButton(
                      onTap: () => widget.onReply(c),
                      semanticLabel: 'Reply',
                      child: const Text('Reply', style: muted),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A compact action with a comfortable (44px) tap target and a visible ripple.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.child, required this.onTap, required this.semanticLabel});
  final Widget child;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: semanticLabel,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(widthFactor: 1, child: child),
        ),
      ),
    ),
  );
}
