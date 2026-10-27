import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../address/presentation/address_proof_gate.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/data/home_models.dart';
import '../../payments/data/payment_charge.dart';
import '../../payments/presentation/payment_method_screen.dart';
import '../data/my_activity_models.dart';
import '../discovery_repository.dart';
import '../group_lists_refresh.dart';
import 'create_group_screen.dart';
import 'group_profile_screen.dart';
import 'widgets/discover_cards.dart';
import '../../../core/navigation/push_guard.dart';

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

  void _openDetail(int id) => context.pushPage(MaterialPageRoute(builder: (_) => GroupProfileScreen(id: id)));

  Future<void> _edit(int id) async {
    try {
      final detail = await ref.read(discoveryRepositoryProvider).group(id);
      if (!mounted) return;
      await context.pushPage(MaterialPageRoute(builder: (_) => CreateGroupScreen(group: detail)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open group')));
    }
  }

  /// Groups with a Join in flight (their button shows a spinner and ignores taps).
  final _joining = <int>{};

  /// Groups just joined or requested: off "Groups near you" at once, before the lists reload.
  final _left = <int>{};

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));

  /// Join from "Groups near you". A free group joins at once; a paid one goes through payment
  /// first (the server admits only once it's paid). Either way the member hears how it went,
  /// and the group moves to "Groups Joined" — or just leaves this list while it awaits the
  /// admin's approval.
  Future<void> _join(GroupItem g) async {
    if (!_joining.add(g.id)) return; // already joining
    setState(() {});
    // Joining needs an address proof (BUG-084); the button spins while that's checked.
    if (!await hasAddressProof(ref)) {
      _joining.remove(g.id);
      if (!mounted) return;
      setState(() {});
      return showAddressProofRequired(context, action: 'join a group');
    }
    if (!mounted) return;
    try {
      if (g.isPaid) return await _payToJoin(g);
      final status = await ref.read(discoveryRepositoryProvider).joinGroup(g.id);
      if (!mounted) return;
      _joined(g, pending: status == 'pending_approval');
    } on DioException catch (e) {
      if (!mounted) return;
      if (handleAddressProofError(context, e, action: 'join a group')) return;
      final err = ApiException.fromDio(e);
      if (err.statusCode == 402) return await _payToJoin(g); // it became paid since the list loaded
      _toast(err.statusCode == 400 || err.statusCode == 409 ? err.message : 'Could not join ${g.title}');
    } catch (_) {
      if (mounted) _toast('Could not join ${g.title}');
    } finally {
      _joining.remove(g.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _payToJoin(GroupItem g) async {
    final paid = await context.pushPage<bool>(MaterialPageRoute(
      builder: (_) => PaymentMethodScreen(charge: groupCharge(g.id), total: g.price ?? 0),
    ));
    if (!mounted) return;
    if (paid == true) {
      _joined(g, pending: g.needsApproval, paid: true);
    } else {
      _toast("Payment not completed — you haven't joined");
    }
  }

  void _joined(GroupItem g, {required bool pending, bool paid = false}) {
    setState(() => _left.add(g.id));
    _toast(pending
        ? '${paid ? 'Paid — r' : 'R'}equest sent. The admin will approve you.'
        : 'You joined ${g.title}');
    // Every list showing this group, and its page, reload.
    ref.invalidateGroupLists(groupId: g.id);
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
              async: nearby.whenData((all) => all.where((g) => !_left.contains(g.id)).toList()),
              expanded: _nearbyExpanded,
              onSeeMore: () => setState(() => _nearbyExpanded = true),
              onTap: _openDetail,
              onJoin: _join,
              joining: _joining,
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
    required this.joining,
  });
  final AsyncValue<List<GroupItem>> async;
  final bool expanded;
  final VoidCallback onSeeMore;
  final void Function(int) onTap;
  final void Function(GroupItem) onJoin;
  final Set<int> joining;

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
                trailing: joining.contains(g.id)
                    ? const SizedBox(
                        width: 58,
                        height: 26,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          ),
                        ),
                      )
                    : JoinButton(onTap: () => onJoin(g)),
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
