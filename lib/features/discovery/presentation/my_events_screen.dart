import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/data/home_models.dart';
import '../data/my_activity_models.dart';
import '../discovery_repository.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';
import 'widgets/discover_cards.dart';

/// The current user's own events — hosted, joined, and nearby. Reached from
/// Profile → Personal → Events.
class MyEventsScreen extends ConsumerStatefulWidget {
  const MyEventsScreen({super.key});

  @override
  ConsumerState<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends ConsumerState<MyEventsScreen> {
  bool _hostedExpanded = false;
  bool _joinedExpanded = false;
  bool _nearbyExpanded = false;

  void _openDetail(int id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(id: id)));

  Future<void> _edit(int id) async {
    try {
      final detail = await ref.read(discoveryRepositoryProvider).event(id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreateEventScreen(event: detail)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open event')));
    }
  }

  Future<void> _join(int id) async {
    try {
      await ref.read(discoveryRepositoryProvider).joinEvent(id);
      ref.invalidate(eventsProvider);
      ref.invalidate(myEventsProvider);
      await ref.read(eventsProvider.future);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not join event')));
    }
  }

  bool _isPast(WorkshopItem e) {
    if (e.date == null) return false;
    final today = DateTime.now();
    return e.date!.isBefore(DateTime(today.year, today.month, today.day));
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
              items: (m) => m.hosted,
              expanded: _hostedExpanded,
              onSeeMore: () => setState(() => _hostedExpanded = true),
              cardBuilder: (e) => EventCard(
                event: e,
                onTap: () => _openDetail(e.id),
                trailing: _isPast(e)
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(8)),
                        child: const Text('Completed', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                      )
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
              items: (m) => m.attending,
              expanded: _joinedExpanded,
              onSeeMore: () => setState(() => _joinedExpanded = true),
              cardBuilder: (e) => EventCard(
                event: e,
                onTap: () => _openDetail(e.id),
                trailing: const JoinedBadge(),
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
      data: (all) {
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
