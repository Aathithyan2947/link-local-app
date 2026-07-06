import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/data/home_models.dart';
import '../../home/data/home_repository.dart';
import '../discovery_repository.dart';
import 'service_provider_detail_screen.dart';
import 'widgets/discover_cards.dart';

void openServiceProvider(BuildContext context, int id) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ServiceProviderDetailScreen(id: id)),
  );
}

/// Unified discovery surface reached from the Services / Events / Groups bottom
/// tabs. Presents four in-screen tabs (All · Events · Service Providers ·
/// Groups) over a shared, live search box. Matches the Figma "Events" /
/// "Service Providers" / "Groups" / "Search results" frames.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key, this.onBack});

  /// Invoked by the header back chevron (returns to Home in the shell).
  final VoidCallback? onBack;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  late final TextEditingController _search;

  static const _titles = [
    'Search for Events, Services & Groups',
    'Events near you',
    'Local Service Providers nearby',
    'Common Groups',
  ];

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(discoverQueryProvider));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<T> _filter<T>(List<T> list, String q, String Function(T) key) {
    if (q.isEmpty) return list;
    final needle = q.toLowerCase();
    return list.where((e) => key(e).toLowerCase().contains(needle)).toList();
  }

  void _selectTab(int i) => ref.read(discoverTabProvider.notifier).set(i);

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(discoverTabProvider);
    final query = ref.watch(discoverQueryProvider);

    final eventsAsync = ref.watch(eventsProvider);
    final spAsync = ref.watch(serviceProvidersProvider);
    final groupsAsync = ref.watch(groupsProvider);

    final eventsData = eventsAsync.asData?.value ?? const <WorkshopItem>[];
    final spData = spAsync.asData?.value ?? const <ServiceProviderItem>[];
    final groupsData = groupsAsync.asData?.value ?? const <GroupItem>[];

    // Match across every user-meaningful field so typing a service, a
    // subcategory, a person's name, a location or an organiser all return hits.
    final events = _filter(
        eventsData, query, (e) => '${e.title} ${e.location ?? ''} ${e.creatorName ?? ''}');
    final sps = _filter(spData, query, (e) => e.searchText);
    final groups = _filter(groupsData, query, (e) => '${e.title} ${e.ownerName ?? ''}');
    final city = ref.watch(homeFeedProvider).asData?.value.city?.name ?? 'your area';

    // Distinguish "still loading" from "genuinely empty" so the initial fetch
    // shows a spinner instead of the "nothing found" state.
    final nothingLoaded = eventsData.isEmpty && spData.isEmpty && groupsData.isEmpty;
    final anyLoading = eventsAsync.isLoading || spAsync.isLoading || groupsAsync.isLoading;
    final anyError = eventsAsync.hasError && spAsync.hasError && groupsAsync.hasError;

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          _Header(
            title: _titles[tab],
            controller: _search,
            activeTab: tab,
            counts: [events.length + sps.length + groups.length, events.length, sps.length, groups.length],
            onBack: widget.onBack,
            onTab: _selectTab,
            onQuery: (v) => ref.read(discoverQueryProvider.notifier).set(v),
          ),
          Expanded(
            child: (nothingLoaded && anyLoading)
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : (nothingLoaded && anyError)
                    ? _DiscoverError(onRetry: () {
                        ref.invalidate(eventsProvider);
                        ref.invalidate(serviceProvidersProvider);
                        ref.invalidate(groupsProvider);
                      })
                    : switch (tab) {
                        1 => _EventsList(events: events, city: city),
                        2 => _SpList(sps: sps, city: city),
                        3 => _GroupsList(groups: groups, city: city),
                        _ => _AllList(
                            events: events,
                            sps: sps,
                            groups: groups,
                            city: city,
                            query: query,
                            onSeeMore: _selectTab,
                          ),
                      },
          ),
        ],
      ),
    );
  }
}

// ── Green header (title · search · tab row) ──────────────────
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.controller,
    required this.activeTab,
    required this.counts,
    required this.onBack,
    required this.onTab,
    required this.onQuery,
  });
  final String title;
  final TextEditingController controller;
  final int activeTab;
  final List<int> counts;
  final VoidCallback? onBack;
  final ValueChanged<int> onTab;
  final ValueChanged<String> onQuery;

  static const _labels = ['All', 'Events', 'Service Providers', 'Groups'];

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 0),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onBack,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.chevron_left, color: Colors.white, size: 28),
                ),
              ),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Search field
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Icons.search, color: AppColors.ink, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onQuery,
                    textInputAction: TextInputAction.search,
                    cursorColor: AppColors.primary,
                    style: const TextStyle(fontSize: 15, color: AppColors.ink),
                    // Fully transparent so the whole white pill is the field —
                    // otherwise the global input theme paints a smaller inner box.
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      hintText: 'Search',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (_, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          onTap: () {
                            controller.clear();
                            onQuery('');
                          },
                          child: const Icon(Icons.close, color: AppColors.ink, size: 20),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tab row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(4, (i) {
              return _TabItem(
                label: _labels[i],
                count: counts[i],
                active: i == activeTab,
                onTap: () => onTab(i),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.label, required this.count, required this.active, required this.onTap});
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        color: active ? Colors.white : Colors.white70,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14)),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: const BoxDecoration(color: Color(0x33000000), shape: BoxShape.rectangle, borderRadius: BorderRadius.all(Radius.circular(9))),
                  child: Text('$count',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Container(
            height: 2.5,
            width: 26,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header with location dropdown ────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.prefix, required this.city, required this.count});
  final String prefix;
  final String city;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Flexible(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink),
                children: [
                  TextSpan(text: '$prefix '),
                  TextSpan(text: '$city($count)', style: const TextStyle(color: AppColors.primary)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 22),
        ],
      ),
    );
  }
}

class _SeeMore extends StatelessWidget {
  const _SeeMore({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onTap,
        child: const Text('See More',
            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    );
  }
}

class _DiscoverError extends StatelessWidget {
  const _DiscoverError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 52, color: AppColors.textMuted),
            const SizedBox(height: 14),
            const Text("Couldn't load results", style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(icon, size: 52, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}

// ── Per-tab lists ────────────────────────────────────────────
class _EventsList extends ConsumerWidget {
  const _EventsList({required this.events, required this.city});
  final List<WorkshopItem> events;
  final String city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(eventsProvider),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SectionHeader(prefix: 'Events in', city: city, count: events.length),
          if (events.isEmpty)
            const _EmptyState(icon: Icons.event_busy_outlined, message: 'No events found')
          else
            ...events.map((e) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: EventCard(event: e),
                )),
        ],
      ),
    );
  }
}

class _SpList extends ConsumerWidget {
  const _SpList({required this.sps, required this.city});
  final List<ServiceProviderItem> sps;
  final String city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(serviceProvidersProvider),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SectionHeader(prefix: 'Service Providers in', city: city, count: sps.length),
          if (sps.isEmpty)
            const _EmptyState(icon: Icons.person_search_outlined, message: 'No service providers found')
          else
            ...sps.map((sp) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: SpCard(sp: sp, city: city, onTap: () => openServiceProvider(context, sp.id)),
                )),
        ],
      ),
    );
  }
}

class _GroupsList extends ConsumerWidget {
  const _GroupsList({required this.groups, required this.city});
  final List<GroupItem> groups;
  final String city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(groupsProvider),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SectionHeader(prefix: 'Groups in', city: city, count: groups.length),
          if (groups.isEmpty)
            const _EmptyState(icon: Icons.groups_outlined, message: 'No groups found')
          else
            ...groups.map((g) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: GroupCard(group: g),
                )),
        ],
      ),
    );
  }
}

// ── "All" combined view ──────────────────────────────────────
class _AllList extends StatelessWidget {
  const _AllList({
    required this.events,
    required this.sps,
    required this.groups,
    required this.city,
    required this.query,
    required this.onSeeMore,
  });
  final List<WorkshopItem> events;
  final List<ServiceProviderItem> sps;
  final List<GroupItem> groups;
  final String city;
  final String query;
  final ValueChanged<int> onSeeMore;

  @override
  Widget build(BuildContext context) {
    final total = events.length + sps.length + groups.length;
    if (total == 0) {
      return _EmptyState(
        icon: query.isEmpty ? Icons.inbox_outlined : Icons.search_off_rounded,
        message: query.isEmpty ? 'Nothing here yet' : 'Nothing matches your search',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text('$total Results for "$query"',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
          ),
        if (events.isNotEmpty) ...[
          _SectionHeader(prefix: 'Events in', city: city, count: events.length),
          ...events.take(2).map((e) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: EventCard(event: e),
              )),
          if (events.length > 2) _SeeMore(onTap: () => onSeeMore(1)),
        ],
        if (sps.isNotEmpty) ...[
          _SectionHeader(prefix: 'Service Providers in', city: city, count: sps.length),
          ...sps.take(2).map((sp) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SpCard(sp: sp, city: city, onTap: () => openServiceProvider(context, sp.id)),
              )),
          if (sps.length > 2) _SeeMore(onTap: () => onSeeMore(2)),
        ],
        if (groups.isNotEmpty) ...[
          _SectionHeader(prefix: 'Groups in', city: city, count: groups.length),
          ...groups.take(2).map((g) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: GroupCard(group: g),
              )),
          if (groups.length > 2) _SeeMore(onTap: () => onSeeMore(3)),
        ],
      ],
    );
  }
}
