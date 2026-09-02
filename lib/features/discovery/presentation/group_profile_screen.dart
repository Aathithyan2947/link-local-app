import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/data/home_models.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../../home/data/home_repository.dart';
import '../../home/presentation/widgets/area_picker_sheet.dart';
import '../../profile/data/profile_repository.dart';
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
  SectionAreaOverride? _areaFilter;

  DiscoveryRepository get _repo => ref.read(discoveryRepositoryProvider);

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(groupDetailProvider(widget.id));
      await ref.read(groupDetailProvider(widget.id).future);
      if (!mounted) return;
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

  /// Same picker Home uses for its per-section area scoping.
  Future<void> _pickArea(GroupDetail g) async {
    final cityId = ref.read(myProfileProvider).asData?.value.cityId;
    final picked = await showAreaPickerSheet(context, cityId: cityId);
    if (picked != null && mounted) {
      setState(() => _areaFilter = SectionAreaOverride(areaId: picked.id, label: picked.areaName));
    }
  }

  Future<void> _setMuted(GroupDetail g, bool muted) =>
      _run(() => _repo.setGroupMuted(g.id, muted), muted ? 'Notifications muted' : 'Notifications on');

  Future<void> _clearChat(GroupDetail g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
            'This hides the current discussions from your view only. Other members keep seeing them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) await _run(() => _repo.clearGroupChat(g.id), 'Chat cleared');
  }

  void _showMembers(GroupDetail g) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: FutureBuilder<List<GroupMember>>(
          future: _repo.groupMembers(g.id),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              );
            }
            final members = snap.data ?? const <GroupMember>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text('Members (${members.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                ),
                if (snap.hasError)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Text("Couldn't load members", style: TextStyle(color: AppColors.textSecondary)),
                  )
                else if (members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Text('No members yet.', style: TextStyle(color: AppColors.textMuted)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: members.length,
                      itemBuilder: (_, i) {
                        final m = members[i];
                        return ListTile(
                          leading: Avatar(name: m.name, photoUrl: m.photoUrl, radius: 20),
                          title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: m.isCreator
                              ? const Text('Group creator', style: TextStyle(color: AppColors.primary))
                              : null,
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
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
          onRefresh: () => ref.refresh(groupDetailProvider(widget.id).future),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _header(g),
              if (!g.isMember) _joinCta(g),
              _discussions(g),
              if (g.isMember) ...[
                const SizedBox(height: 12),
                _muteTile(g),
                const SizedBox(height: 12),
                _dangerTile(g),
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
                _action(Icons.groups_rounded, '${g.membersCount} Members', () => _showMembers(g)),
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
  Widget _discussions(GroupDetail g) {
    // Default slice comes with the group; picking an area swaps in a scoped fetch, and the
    // previous list stays on screen while that lands so the section doesn't flicker.
    final scoped = _areaFilter != null
        ? ref.watch(groupDiscussionsScopedProvider(GroupAreaKey(g.id, _areaFilter!.areaId)))
        : null;
    final discussions = scoped?.asData?.value ?? g.discussions;
    final areaLabel = _areaFilter?.label ?? g.area;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (g.isMember)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _post(g),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Post'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickArea(g),
            child: Row(
              children: [
                Flexible(
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink),
                      children: [
                        const TextSpan(text: 'Group Discussions'),
                        if (areaLabel != null && areaLabel.isNotEmpty)
                          TextSpan(text: ' in $areaLabel', style: const TextStyle(color: AppColors.primary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 22),
              ],
            ),
          ),
          const Text('Ask questions, share updates, and connect with your community',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          if (discussions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _areaFilter == null
                      ? 'No discussions yet.'
                      : 'No discussions from ${_areaFilter!.label} yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          else
            ...discussions.map((d) => _discussionTile(d)),
        ],
      ),
    );
  }

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

  // ── Mute notifications ─────────────────────────────────────
  Widget _muteTile(GroupDetail g) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              const Icon(Icons.notifications_none_rounded, color: AppColors.ink, size: 22),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('Mute Notifications',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
              ),
              Switch(
                value: g.isMuted,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.primary,
                onChanged: _busy ? null : (v) => _setMuted(g, v),
              ),
            ],
          ),
        ),
      );

  // ── Clear chat / Exit group ────────────────────────────────
  Widget _dangerTile(GroupDetail g) {
    // The creator cannot leave their own group, but can still clear their own view of it.
    final canExit = !g.isCreator;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _dangerRow(Icons.delete_outline, 'Clear chat', () => _clearChat(g), last: !canExit),
            if (canExit) _dangerRow(Icons.logout, 'Exit Group', () => _leave(g), last: true),
          ],
        ),
      ),
    );
  }

  Widget _dangerRow(IconData icon, String label, VoidCallback onTap, {required bool last}) => InkWell(
        onTap: _busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.error, size: 22),
              const SizedBox(width: 14),
              Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.error)),
            ],
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
