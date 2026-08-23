import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/data/home_models.dart';
import '../data/my_activity_models.dart';
import '../discovery_repository.dart';
import 'create_group_screen.dart';
import 'group_profile_screen.dart';
import 'widgets/discover_cards.dart';

/// The current user's own groups — owned, joined, and nearby. Reached from
/// Profile → Personal → Groups.
class MyGroupsScreen extends ConsumerStatefulWidget {
  const MyGroupsScreen({super.key});

  @override
  ConsumerState<MyGroupsScreen> createState() => _MyGroupsScreenState();
}

class _MyGroupsScreenState extends ConsumerState<MyGroupsScreen> {
  bool _ownedExpanded = false;
  bool _joinedExpanded = false;
  bool _nearbyExpanded = false;

  void _openDetail(int id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupProfileScreen(id: id)));

  Future<void> _edit(int id) async {
    try {
      final detail = await ref.read(discoveryRepositoryProvider).group(id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreateGroupScreen(group: detail)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open group')));
    }
  }

  Future<void> _join(int id) async {
    try {
      await ref.read(discoveryRepositoryProvider).joinGroup(id);
      ref.invalidate(groupsProvider);
      ref.invalidate(myGroupsProvider);
      await ref.read(groupsProvider.future);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not join group')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myGroups = ref.watch(myGroupsProvider);
    final nearby = ref.watch(groupsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.primary, foregroundColor: Colors.white, title: const Text('My Groups')),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => Future.wait([ref.refresh(myGroupsProvider.future), ref.refresh(groupsProvider.future)]),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section(
              title: 'Your Groups',
              async: myGroups,
              items: (m) => m.owned,
              expanded: _ownedExpanded,
              onSeeMore: () => setState(() => _ownedExpanded = true),
              cardBuilder: (g) => GroupCard(
                group: g,
                onTap: () => _openDetail(g.id),
                trailing: OutlinedButton.icon(
                  onPressed: () => _edit(g.id),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    minimumSize: const Size(0, 30),
                    side: const BorderSide(color: AppColors.primary),
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _Section(
              title: 'Groups Joined',
              async: myGroups,
              items: (m) => m.joined,
              expanded: _joinedExpanded,
              onSeeMore: () => setState(() => _joinedExpanded = true),
              cardBuilder: (g) => GroupCard(group: g, onTap: () => _openDetail(g.id), trailing: const JoinedBadge()),
            ),
            const SizedBox(height: 20),
            _NearbySection(
              async: nearby,
              expanded: _nearbyExpanded,
              onSeeMore: () => setState(() => _nearbyExpanded = true),
              onTap: _openDetail,
              onJoin: _join,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.async,
    required this.items,
    required this.expanded,
    required this.onSeeMore,
    required this.cardBuilder,
  });
  final AsyncValue<MyGroups> async;
  final String title;
  final List<GroupItem> Function(MyGroups) items;
  final bool expanded;
  final VoidCallback onSeeMore;
  final Widget Function(GroupItem) cardBuilder;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('$e')),
      data: (m) {
        final all = items(m);
        if (all.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
              const SizedBox(height: 8),
              const Text('Nothing here yet.', style: TextStyle(color: AppColors.textMuted)),
            ],
          );
        }
        final shown = expanded ? all : all.take(2).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
            const SizedBox(height: 10),
            for (final g in shown) ...[cardBuilder(g), const SizedBox(height: 10)],
            if (!expanded && all.length > shown.length)
              Center(child: TextButton(onPressed: onSeeMore, child: const Text('See More'))),
          ],
        );
      },
    );
  }
}

class _NearbySection extends StatelessWidget {
  const _NearbySection({
    required this.async,
    required this.expanded,
    required this.onSeeMore,
    required this.onTap,
    required this.onJoin,
  });
  final AsyncValue<List<GroupItem>> async;
  final bool expanded;
  final VoidCallback onSeeMore;
  final void Function(int) onTap;
  final void Function(int) onJoin;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('$e')),
      data: (all) {
        final shown = expanded ? all : all.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Groups near you', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
            const SizedBox(height: 10),
            if (shown.isEmpty) const Text('No groups nearby yet.', style: TextStyle(color: AppColors.textMuted)),
            for (final g in shown) ...[
              GroupCard(
                group: g,
                onTap: () => onTap(g.id),
                trailing: JoinButton(onTap: () => onJoin(g.id)),
              ),
              const SizedBox(height: 10),
            ],
            if (!expanded && all.length > shown.length)
              Center(child: TextButton(onPressed: onSeeMore, child: const Text('See More'))),
          ],
        );
      },
    );
  }
}
