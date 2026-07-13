import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/data/home_models.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../data/group_detail_models.dart';
import '../discovery_repository.dart';

/// Full interest-group profile — the "Group Info" frame. Join / pay (mock) /
/// leave, post to the group, and view group discussions.
class GroupProfileScreen extends ConsumerStatefulWidget {
  const GroupProfileScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends ConsumerState<GroupProfileScreen> {
  bool _busy = false;

  DiscoveryRepository get _repo => ref.read(discoveryRepositoryProvider);

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(groupDetailProvider(widget.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(GroupDetail g) => _run(() async {
        await _repo.joinGroup(g.id);
        if (g.isPaid) await _repo.payForGroup(g.id); // MOCK payment
      }, g.isPaid ? 'Joined — payment successful' : 'You have joined!');

  Future<void> _leave(GroupDetail g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit group?'),
        content: Text('You will leave "${g.title}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Exit', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) await _run(() => _repo.leaveGroup(g.id), 'You have left the group');
  }

  Future<void> _post(GroupDetail g) async {
    final controller = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Share with the group', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'What would you like to share?'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Post'),
            ),
          ],
        ),
      ),
    );
    if (text != null && text.isNotEmpty) {
      await _run(() => _repo.postToGroup(g.id, text: text), 'Posted to the group');
    }
  }

  void _showGuidelines(GroupDetail g) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Guidelines', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 10),
            Text(g.description?.isNotEmpty == true ? g.description! : 'No guidelines added yet.',
                style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(groupDetailProvider(widget.id));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _error(),
        data: (g) => RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(groupDetailProvider(widget.id)),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _header(g),
              if (!g.isMember) _joinCta(g),
              _discussions(g),
              if (g.isMember && !g.isCreator) ...[
                const SizedBox(height: 8),
                _exitTile(g),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Green header + action row ──────────────────────────────
  Widget _header(GroupDetail g) {
    final topPad = MediaQuery.of(context).padding.top;
    final created = g.createdAt != null ? DateFormat('MMM d, yy').format(g.createdAt!) : '';
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, topPad + 8, 16, 34),
          decoration: const BoxDecoration(color: AppColors.primary),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 6),
                  const Text('Group Info', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 12),
              _groupAvatar(g),
              const SizedBox(height: 12),
              Text(g.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 22)),
              const SizedBox(height: 4),
              Text('Created by ${g.creatorName}${created.isNotEmpty ? '  •  $created' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -22),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Row(
              children: [
                _action(Icons.groups_rounded, '${g.membersCount} Members', () {}),
                _divider(),
                _action(Icons.person_add_alt_1, 'Add Person',
                    () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invites coming soon')))),
                _divider(),
                _action(Icons.info_outline, 'Guidelines', () => _showGuidelines(g)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _groupAvatar(GroupDetail g) {
    if (g.photoUrl != null && g.photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 44,
        backgroundColor: Colors.white24,
        backgroundImage: CachedNetworkImageProvider(AppConfig.assetUrl(g.photoUrl!)),
      );
    }
    return const CircleAvatar(
      radius: 44,
      backgroundColor: Colors.white24,
      child: Icon(Icons.groups_rounded, color: Colors.white, size: 40),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 24),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ],
          ),
        ),
      );

  Widget _divider() => Container(width: 1, height: 34, color: AppColors.border);

  // ── Join CTA (non-members) ─────────────────────────────────
  Widget _joinCta(GroupDetail g) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy ? null : () => _join(g),
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(g.isPending
                    ? 'Requested — pending approval'
                    : g.isPaid
                        ? 'Join for ₹${(g.price ?? 0).toStringAsFixed(0)}'
                        : 'Join Group'),
          ),
        ),
      );

  // ── Group discussions ──────────────────────────────────────
  Widget _discussions(GroupDetail g) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Group Discussions',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
                ),
                if (g.isMember)
                  TextButton.icon(
                    onPressed: () => _post(g),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Post'),
                  ),
              ],
            ),
            const Text('Ask questions, share updates, and connect with your community',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            if (g.discussions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No discussions yet.', style: TextStyle(color: AppColors.textMuted)),
                ),
              )
            else
              ...g.discussions.map((d) => _discussionTile(d)),
          ],
        ),
      );

  Widget _discussionTile(DiscussionItem d) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(name: d.authorName, photoUrl: d.authorPhoto, radius: 16),
                const SizedBox(width: 10),
                Text(d.authorName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              ],
            ),
            if (d.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(d.text, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.favorite_border, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 5),
                Text('${d.likes}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(width: 16),
                const Icon(Icons.mode_comment_outlined, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 5),
                Text('${d.comments} Replies', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      );

  Widget _exitTile(GroupDetail g) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: OutlinedButton.icon(
          onPressed: _busy ? null : () => _leave(g),
          icon: const Icon(Icons.logout, color: AppColors.error, size: 18),
          label: const Text('Exit Group', style: TextStyle(color: AppColors.error)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: AppColors.error),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  Widget _error() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 52, color: AppColors.textMuted),
              const SizedBox(height: 14),
              const Text("Couldn't load this group", style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              OutlinedButton(
                  onPressed: () => ref.invalidate(groupDetailProvider(widget.id)), child: const Text('Retry')),
            ],
          ),
        ),
      );
}
