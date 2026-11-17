import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/push_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../../messages/presentation/chat_screen.dart';
import '../data/group_detail_models.dart';
import '../discovery_repository.dart';
import 'service_provider_detail_screen.dart';
import 'user_profile_screen.dart';

/// A group's members, laid out as the Figma's "Group Members" page (BUG-082): admins first,
/// then members, each with the month they joined. A name opens that member; the chat icon
/// messages them. Members whose profile is private to the viewer are counted, not listed.
class GroupMembersScreen extends ConsumerStatefulWidget {
  const GroupMembersScreen({super.key, required this.groupId});
  final int groupId;

  @override
  ConsumerState<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends ConsumerState<GroupMembersScreen> {
  late Future<GroupMembers> _members = _load();
  final _search = TextEditingController();

  Future<GroupMembers> _load() => ref.read(discoveryRepositoryProvider).groupMembers(widget.groupId);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openProfile(GroupMember m, int profileId) {
    final mine = m.userId == ref.read(authControllerProvider).user?.id;
    context.pushPage(MaterialPageRoute(
      builder: (_) => mine || m.isServiceProvider
          ? ServiceProviderDetailScreen(id: profileId)
          : UserProfileScreen(id: profileId),
    ));
  }

  void _message(GroupMember m) => context.pushPage(MaterialPageRoute(
        builder: (_) => ChatScreen(otherUserId: m.userId, otherName: m.name, otherPhoto: m.photoUrl),
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          Expanded(
            child: FutureBuilder<GroupMembers>(
              future: _members,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Couldn't load the members", style: TextStyle(color: AppColors.textSecondary)),
                        TextButton(
                          onPressed: () => setState(() => _members = _load()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                return _list(snap.data!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(GroupMembers data) {
    final meId = ref.watch(authControllerProvider).user?.id;
    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty ? data.members : data.members.where((m) => m.name.toLowerCase().contains(q)).toList();
    final admins = shown.where((m) => m.isAdmin).toList();
    final others = shown.where((m) => !m.isAdmin).toList();
    final hidden = data.hiddenCount;

    Widget row(GroupMember m) {
      final profileId = m.profileId;
      return _MemberRow(
        key: ValueKey('group-member-${m.userId}'),
        member: m,
        isMe: m.userId == meId,
        onTap: profileId == null ? null : () => _openProfile(m, profileId),
        onMessage: () => _message(m),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _SearchField(controller: _search, onChanged: () => setState(() {})),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text('Total Members ${data.members.length + hidden}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
        ),
        if (admins.isNotEmpty) ...[
          _SectionLabel('Admin (${admins.length})'),
          for (final m in admins) row(m),
        ],
        if (others.isNotEmpty) ...[
          _SectionLabel('Members (${others.length})'),
          for (final m in others) row(m),
        ],
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Center(
              child: Text(
                q.isEmpty ? 'No members yet.' : 'No members match "${_search.text.trim()}".',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text(
                  hidden == 1 ? '1 member has a private profile' : '$hidden members have private profiles',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      color: AppColors.primary,
      padding: EdgeInsets.fromLTRB(16, topPad + 14, 16, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.chevron_left, color: Colors.white, size: 28),
            ),
          ),
          const Text('Group Members',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.ink, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              textInputAction: TextInputAction.search,
              cursorColor: AppColors.primary,
              style: const TextStyle(fontSize: 15, color: AppColors.ink),
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search members...',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 15),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged();
              },
              child: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
        child: Text(text, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500, fontSize: 16)),
      );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({super.key, required this.member, required this.isMe, required this.onTap, required this.onMessage});
  final GroupMember member;
  final bool isMe;
  final VoidCallback? onTap;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final joined = m.joinedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                Avatar(name: m.name, photoUrl: m.photoUrl, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: AppColors.ink)),
                      if (joined != null) ...[
                        const SizedBox(height: 2),
                        Text('Joined ${DateFormat('MMM, y').format(joined)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                if (isMe)
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.primary),
                    ),
                    child: const Text('You',
                        style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w500)),
                  )
                else
                  IconButton(
                    tooltip: 'Message ${m.name}',
                    onPressed: onMessage,
                    icon: const Icon(Icons.message_rounded, color: AppColors.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
