import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../address/presentation/address_proof_gate.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/data/home_models.dart';
import '../data/my_activity_models.dart';
import '../discovery_repository.dart';
import '../event_lists_refresh.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';
import 'widgets/discover_cards.dart';
import '../../../core/navigation/push_guard.dart';

/// The current user's own events — hosted, joined, past and nearby. Reached from
/// Profile → Personal → Events.
///
/// Hosted and Joined list only events that aren't over (an "Ongoing" chip while one runs);
/// once over they move to Past Events, marked Closed (BUG-101/102). "Events near you" offers
/// only events still open to join, not the member's own or ones they're already in.
class MyEventsScreen extends ConsumerStatefulWidget {
  const MyEventsScreen({super.key});

  @override
  ConsumerState<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends ConsumerState<MyEventsScreen> {
  bool _hostedExpanded = false;
  bool _joinedExpanded = false;
  bool _pastExpanded = false;
  bool _nearbyExpanded = false;

  /// Hosted and joined events that are over, most recent first (each once).
  static List<WorkshopItem> _past(MyEvents m) {
    final hostedIds = {for (final e in m.hosted) e.id};
    final past = [
      ...m.hosted.where((e) => e.hasEnded),
      ...m.attending.where((e) => e.hasEnded && !hostedIds.contains(e.id)),
    ];
    DateTime at(WorkshopItem e) {
      final d = e.date ?? DateTime(0);
      return DateTime(d.year, d.month, d.day, e.startTime?.hour ?? 0, e.startTime?.minute ?? 0);
    }
    return past..sort((a, b) => at(b).compareTo(at(a)));
  }

  void _openDetail(int id) => context.pushPage(MaterialPageRoute(builder: (_) => EventDetailScreen(id: id)));

  Future<void> _edit(int id) async {
    try {
      final detail = await ref.read(discoveryRepositoryProvider).event(id);
      if (!mounted) return;
      await context.pushPage(MaterialPageRoute(builder: (_) => CreateEventScreen(event: detail)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open event')));
    }
  }

  Future<void> _join(int id) async {
    if (!await ensureAddressProof(context, ref, action: 'join an event')) return;
    try {
      await ref.read(discoveryRepositoryProvider).joinEvent(id);
      ref.invalidateEventLists();
      await ref.read(eventsProvider.future);
    } catch (e) {
      if (!mounted || handleAddressProofError(context, e, action: 'join an event')) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not join event')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myEvents = ref.watch(myEventsProvider);
    final nearby = ref.watch(eventsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.primary, foregroundColor: Colors.white, title: const Text('My Events')),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => Future.wait([ref.refresh(myEventsProvider.future), ref.refresh(eventsProvider.future)]),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section(
              title: 'Events Hosted',
              async: myEvents,
              items: (m) => m.hosted.where((e) => !e.hasEnded).toList(),
              expanded: _hostedExpanded,
              onSeeMore: () => setState(() => _hostedExpanded = true),
              cardBuilder: (e) => EventCard(
                event: e,
                onTap: () => _openDetail(e.id),
                trailing: e.hasStarted
                    ? const EventStateChip.ongoing()
                    : OutlinedButton.icon(
                        onPressed: () => _edit(e.id),
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
              title: 'Events Joined',
              async: myEvents,
              items: (m) => m.attending.where((e) => !e.hasEnded).toList(),
              expanded: _joinedExpanded,
              onSeeMore: () => setState(() => _joinedExpanded = true),
              cardBuilder: (e) => EventCard(
                event: e,
                onTap: () => _openDetail(e.id),
                trailing: e.hasStarted ? const EventStateChip.ongoing() : const JoinedBadge(),
              ),
            ),
            const SizedBox(height: 20),
            // Still opens the event, so attendees can review it.
            _Section(
              title: 'Past Events',
              async: myEvents,
              items: _past,
              expanded: _pastExpanded,
              onSeeMore: () => setState(() => _pastExpanded = true),
              cardBuilder: (e) => EventCard(
                event: e,
                onTap: () => _openDetail(e.id),
                trailing: const EventStateChip.closed(),
              ),
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
  final AsyncValue<MyEvents> async;
  final String title;
  final List<WorkshopItem> Function(MyEvents) items;
  final bool expanded;
  final VoidCallback onSeeMore;
  final Widget Function(WorkshopItem) cardBuilder;

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
            for (final e in shown) ...[cardBuilder(e), const SizedBox(height: 10)],
            if (!expanded && all.length > shown.length)
              Center(
                child: TextButton(onPressed: onSeeMore, child: const Text('See More')),
              ),
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
  final AsyncValue<List<WorkshopItem>> async;
  final bool expanded;
  final VoidCallback onSeeMore;
  final void Function(int) onTap;
  final void Function(int) onJoin;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('$e')),
      data: (loaded) {
        // Only events still open to join: not started, not mine, not already joined or asked.
        final all = loaded.where((e) => !e.hasStarted && !e.isHost && e.myStatus == null).toList();
        final shown = expanded ? all : all.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Events near you', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
            const SizedBox(height: 10),
            if (shown.isEmpty) const Text('No events nearby yet.', style: TextStyle(color: AppColors.textMuted)),
            for (final e in shown) ...[
              EventCard(event: e, onTap: () => onTap(e.id), onJoin: () => onJoin(e.id)),
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

/// "Ongoing" (started, not over) or "Closed" (over) on a My Events card.
class EventStateChip extends StatelessWidget {
  const EventStateChip.ongoing({super.key}) : closed = false;
  const EventStateChip.closed({super.key}) : closed = true;
  final bool closed;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: closed ? AppColors.field : AppColors.primarySurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          closed ? 'Closed' : 'Ongoing',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: closed ? FontWeight.w400 : FontWeight.w600,
            color: closed ? AppColors.textSecondary : AppColors.primary,
          ),
        ),
      );
}
