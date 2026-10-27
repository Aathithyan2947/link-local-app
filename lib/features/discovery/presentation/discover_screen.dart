import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/data/home_models.dart';
import '../../home/data/home_repository.dart';
import '../../home/presentation/widgets/area_picker_sheet.dart';
import '../../home/presentation/widgets/service_icons.dart';
import '../../profile/data/profile_repository.dart';
import '../data/service_catalog_models.dart';
import '../discovery_repository.dart';
import 'event_detail_screen.dart';
import 'group_profile_screen.dart';
import 'service_provider_detail_screen.dart';
import 'widgets/discover_cards.dart';
import '../../../core/navigation/push_guard.dart';

void openServiceProvider(BuildContext context, int id) {
  context.pushPage(
    MaterialPageRoute(builder: (_) => ServiceProviderDetailScreen(id: id)),
  );
}

void openEvent(BuildContext context, int id) {
  context.pushPage(
    MaterialPageRoute(builder: (_) => EventDetailScreen(id: id)),
  );
}

void openGroup(BuildContext context, int id) {
  context.pushPage(
    MaterialPageRoute(builder: (_) => GroupProfileScreen(id: id)),
  );
}

/// Unified discovery surface reached from the Services / Events / Groups bottom
/// tabs. Presents four in-screen tabs (All · Events · Service Providers ·
/// Groups) over a shared, live search box. Matches the Figma "Events" /
/// "Service Providers" / "Groups" / "Search results" frames.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key, this.onBack, this.service});

  /// Invoked by the header back chevron (returns to Home in the shell). A pushed copy without
  /// one just goes back.
  final VoidCallback? onBack;

  /// Only this service's providers (BUG-087): the Service Providers list, opened from an All
  /// Services tile. The filter can't be cleared here; going back to All Services picks another.
  /// The area picker and search still work within it, and its search and tab are its own, so
  /// the Services tab underneath keeps its state.
  final CatalogService? service;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  late final TextEditingController _search;

  /// The search within [DiscoverScreen.service]'s providers.
  String _serviceQuery = '';

  static const _titles = [
    'Search for Events, Services & Groups',
    'Events near you',
    'Local Service Providers nearby',
    'Common Groups',
  ];

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.service == null ? ref.read(discoverQueryProvider) : '');
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

  /// The header's area picker (the same sheet as Home's). It sets the app-wide location, so
  /// Home and every other tab follow; the whole-city row returns everything to city-wide.
  Future<void> _pickArea(String city) async {
    final current = ref.read(homeScopeProvider);
    final picked = await showAreaScopeSheet(
      context,
      cityId: ref.read(myProfileProvider).asData?.value.cityId,
      cityName: city,
      selectedAreaId: current.overrideAreaId,
      wholeCitySelected: current.isWholeCity,
    );
    if (picked == null) return;
    final notifier = ref.read(homeScopeProvider.notifier);
    final a = picked.area;
    a == null ? notifier.setScope('city') : notifier.setArea(a.id, a.areaName);
  }

  VoidCallback get _back => widget.onBack ?? () => Navigator.of(context).maybePop();

  /// [DiscoverScreen.service]'s providers in the app-wide location, filtered on the server.
  Widget _buildForService(CatalogService service) {
    final async = ref.watch(providersForServiceProvider(service.id));
    final feed = ref.watch(homeFeedProvider).asData?.value;
    final city = feed?.city?.name ?? 'your area';
    final all = async.asData?.value.items ?? const <ServiceProviderItem>[];
    final sps = _filter(all, _serviceQuery, (e) => e.searchText);
    final count = _serviceQuery.isEmpty ? (async.asData?.value.total ?? sps.length) : sps.length;
    final scope = _Scope(
      place: locationLabel(ref.watch(homeScopeProvider), feed, fallback: city),
      eventsCount: 0,
      spsCount: count,
      groupsCount: 0,
      onPickArea: () => _pickArea(city),
    );
    return Material(
      color: AppColors.background,
      child: Column(
        children: [
          _Header(
            title: _titles[2],
            controller: _search,
            activeTab: 2,
            counts: [count, 0, count, 0],
            onBack: _back,
            onTab: (_) {},
            onQuery: (v) => setState(() => _serviceQuery = v),
            service: service.name,
          ),
          Expanded(
            child: all.isEmpty && async.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : all.isEmpty && async.hasError
                    ? _DiscoverError(onRetry: () => ref.invalidate(providersForServiceProvider(service.id)))
                    : _SpList(
                        sps: sps,
                        scope: scope,
                        prefix: '${service.name} in',
                        emptyMessage: 'No ${service.name} providers found',
                        onRefresh: () => ref.refresh(providersForServiceProvider(service.id).future),
                      ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.service case final service?) return _buildForService(service);
    final tab = ref.watch(discoverTabProvider);
    final query = ref.watch(discoverQueryProvider);

    final eventsAsync = ref.watch(discoverEventsProvider);
    final spAsync = ref.watch(discoverServiceProvidersProvider);
    final groupsAsync = ref.watch(discoverGroupsProvider);
    final location = ref.watch(homeScopeProvider);

    final eventsData = eventsAsync.asData?.value.items ?? const <WorkshopItem>[];
    final spData = spAsync.asData?.value.items ?? const <ServiceProviderItem>[];
    final groupsData = groupsAsync.asData?.value.items ?? const <GroupItem>[];

    // Match across every user-meaningful field so typing a service, a
    // subcategory, a person's name, a location or an organiser all return hits.
    final events = _filter(
        eventsData, query, (e) => '${e.title} ${e.location ?? ''} ${e.creatorName ?? ''}');
    final sps = _filter(spData, query, (e) => e.searchText);
    final groups = _filter(groupsData, query, (e) => '${e.title} ${e.ownerName ?? ''}');
    final feed = ref.watch(homeFeedProvider).asData?.value;
    final city = feed?.city?.name ?? 'your area';
    // Counts: the backend's real total, unless a search is narrowing the loaded list.
    int count<T>(AsyncValue<Section<T>> a, List<T> filtered) =>
        query.isEmpty ? (a.asData?.value.total ?? filtered.length) : filtered.length;
    final scope = _Scope(
      // The same label Home shows for the app-wide location.
      place: locationLabel(location, feed, fallback: city),
      eventsCount: count(eventsAsync, events),
      spsCount: count(spAsync, sps),
      groupsCount: count(groupsAsync, groups),
      onPickArea: () => _pickArea(city),
    );

    // Distinguish "still loading" from "genuinely empty" so the initial fetch
    // shows a spinner instead of the "nothing found" state.
    final nothingLoaded = eventsData.isEmpty && spData.isEmpty && groupsData.isEmpty;
    final anyLoading = eventsAsync.isLoading || spAsync.isLoading || groupsAsync.isLoading;
    final anyError = eventsAsync.hasError && spAsync.hasError && groupsAsync.hasError;

    // Material, not a bare Container: this screen is used both inside HomeShell's Scaffold and
    // pushed as a standalone route by the SP page's "explore" CTAs. In the pushed case there was
    // no Material ancestor, so the header's search TextField threw on build.
    return Material(
      color: AppColors.background,
      child: Column(
        children: [
          _Header(
            title: _titles[tab],
            controller: _search,
            activeTab: tab,
            counts: [
              scope.eventsCount + scope.spsCount + scope.groupsCount,
              scope.eventsCount,
              scope.spsCount,
              scope.groupsCount,
            ],
            onBack: _back,
            onTab: _selectTab,
            onQuery: (v) => ref.read(discoverQueryProvider.notifier).set(v),
          ),
          Expanded(
            child: (nothingLoaded && anyLoading)
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : (nothingLoaded && anyError)
                    ? _DiscoverError(onRetry: () {
                        ref.invalidate(discoverEventsProvider);
                        ref.invalidate(discoverServiceProvidersProvider);
                        ref.invalidate(discoverGroupsProvider);
                      })
                    : switch (tab) {
                        1 => _EventsList(events: events, scope: scope),
                        2 => _SpList(sps: sps, scope: scope),
                        3 => _GroupsList(groups: groups, scope: scope),
                        _ => _AllList(
                            events: events,
                            sps: sps,
                            groups: groups,
                            scope: scope,
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
    this.service,
  });
  final String title;

  /// The service the list is limited to, shown where the tabs are (no tabs then).
  final String? service;
  final TextEditingController controller;
  final int activeTab;
  final List<int> counts;
  final VoidCallback? onBack;
  final ValueChanged<int> onTab;
  final ValueChanged<String> onQuery;

  static const _labels = ['All', 'Events', 'Service Providers', 'Groups'];
  // Says what each tab's search actually matches (BUG-090): see the _filter calls above.
  static const _hints = [
    'Search events, services or groups',
    'Search events, venues or hosts',
    'Search providers or services',
    'Search groups or owners',
  ];

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
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      hintText: service != null ? 'Search providers' : _hints[activeTab],
                      hintStyle: const TextStyle(color: AppColors.textMuted),
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
          // The tab row, or for one service's list, that service in its place.
          if (service != null)
            _ServiceFilter(name: service!)
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              // Tabs shrink to fit rather than overflowing on a narrow screen (the counts are real
              // totals and can run to several digits) — but all by the same factor. Each tab's
              // share of the row is proportional to its natural width, so "Service Providers"
              // can't end up smaller than "All". When everything fits, nothing shrinks.
              children: List.generate(4, (i) {
                return Flexible(
                  flex: (_TabItem.naturalWidth(context, _labels[i], counts[i]) * 10).round(),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _TabItem(
                      label: _labels[i],
                      count: counts[i],
                      active: i == activeTab,
                      onTap: () => onTab(i),
                    ),
                  ),
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

  static const _labelSize = 14.0;
  static const _countSize = 10.0;

  /// How wide a tab is at full size: label (measured bold, so it doesn't change when the tab
  /// is selected), the gap, and the count badge.
  static double naturalWidth(BuildContext context, String label, int count) {
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return measure(label, const TextStyle(fontSize: _labelSize, fontWeight: FontWeight.w700)) +
        5 +
        measure('$count', const TextStyle(fontSize: _countSize, fontWeight: FontWeight.w600)) +
        12;
  }

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
                        fontSize: _labelSize)),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: const BoxDecoration(color: Color(0x33000000), shape: BoxShape.rectangle, borderRadius: BorderRadius.all(Radius.circular(9))),
                  child: Text('$count',
                      style: const TextStyle(color: Colors.white, fontSize: _countSize, fontWeight: FontWeight.w600)),
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

/// The service a pushed provider list is limited to. Not removable: the user goes back to All
/// Services to pick another (BUG-087).
class _ServiceFilter extends StatelessWidget {
  const _ServiceFilter({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          label: 'Showing $name only',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ServiceIcon(serviceName: name, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section header with location dropdown ────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.prefix, required this.place, required this.count, required this.onTap});
  final String prefix;

  /// The city, or the area picked from this header.
  final String place;
  final int count;

  /// Opens the area picker — the ▼ promises a choice, so the whole header is tappable.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Row(
          children: [
            Flexible(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink),
                  children: [
                    TextSpan(text: '$prefix '),
                    TextSpan(text: '$place($count)', style: const TextStyle(color: AppColors.primary)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 22),
          ],
        ),
      ),
    );
  }
}

/// What every Discover section header shows and does: the place in view, each list's
/// count, and how to change the area.
class _Scope {
  const _Scope({
    required this.place,
    required this.eventsCount,
    required this.spsCount,
    required this.groupsCount,
    required this.onPickArea,
  });
  final String place;
  final int eventsCount;
  final int spsCount;
  final int groupsCount;
  final VoidCallback onPickArea;
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
  const _EventsList({required this.events, required this.scope});
  final List<WorkshopItem> events;
  final _Scope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => ref.refresh(discoverEventsProvider.future),
      child: ListView(
        padding: EdgeInsets.only(bottom: 66 + MediaQuery.of(context).padding.bottom + 24),
        children: [
          _SectionHeader(prefix: 'Events in', place: scope.place, count: scope.eventsCount, onTap: scope.onPickArea),
          if (events.isEmpty)
            const _EmptyState(icon: Icons.event_busy_outlined, message: 'No events found')
          else
            ...events.map((e) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: EventCard(event: e, onTap: () => openEvent(context, e.id)),
                )),
        ],
      ),
    );
  }
}

class _SpList extends ConsumerWidget {
  const _SpList({
    required this.sps,
    required this.scope,
    this.prefix = 'Service Providers in',
    this.emptyMessage = 'No service providers found',
    this.onRefresh,
  });
  final List<ServiceProviderItem> sps;
  final _Scope scope;
  final String prefix;
  final String emptyMessage;

  /// Defaults to the whole Service Providers list.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh ?? () => ref.refresh(discoverServiceProvidersProvider.future),
      child: ListView(
        padding: EdgeInsets.only(bottom: 66 + MediaQuery.of(context).padding.bottom + 24),
        children: [
          _SectionHeader(prefix: prefix, place: scope.place, count: scope.spsCount, onTap: scope.onPickArea),
          if (sps.isEmpty)
            _EmptyState(icon: Icons.person_search_outlined, message: emptyMessage)
          else
            ...sps.map((sp) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: SpCard(sp: sp, city: scope.place, onTap: () => openServiceProvider(context, sp.id)),
                )),
        ],
      ),
    );
  }
}

class _GroupsList extends ConsumerWidget {
  const _GroupsList({required this.groups, required this.scope});
  final List<GroupItem> groups;
  final _Scope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => ref.refresh(discoverGroupsProvider.future),
      child: ListView(
        padding: EdgeInsets.only(bottom: 66 + MediaQuery.of(context).padding.bottom + 24),
        children: [
          _SectionHeader(prefix: 'Groups in', place: scope.place, count: scope.groupsCount, onTap: scope.onPickArea),
          if (groups.isEmpty)
            const _EmptyState(icon: Icons.groups_outlined, message: 'No groups found')
          else
            ...groups.map((g) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: GroupCard(group: g, onTap: () => openGroup(context, g.id)),
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
    required this.scope,
    required this.query,
    required this.onSeeMore,
  });
  final List<WorkshopItem> events;
  final List<ServiceProviderItem> sps;
  final List<GroupItem> groups;
  final _Scope scope;
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
          _SectionHeader(prefix: 'Events in', place: scope.place, count: scope.eventsCount, onTap: scope.onPickArea),
          ...events.take(2).map((e) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: EventCard(event: e, onTap: () => openEvent(context, e.id)),
              )),
          if (events.length > 2) _SeeMore(onTap: () => onSeeMore(1)),
        ],
        if (sps.isNotEmpty) ...[
          _SectionHeader(prefix: 'Service Providers in', place: scope.place, count: scope.spsCount, onTap: scope.onPickArea),
          ...sps.take(2).map((sp) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SpCard(sp: sp, city: scope.place, onTap: () => openServiceProvider(context, sp.id)),
              )),
          if (sps.length > 2) _SeeMore(onTap: () => onSeeMore(2)),
        ],
        if (groups.isNotEmpty) ...[
          _SectionHeader(prefix: 'Groups in', place: scope.place, count: scope.groupsCount, onTap: scope.onPickArea),
          ...groups.take(2).map((g) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: GroupCard(group: g, onTap: () => openGroup(context, g.id)),
              )),
          if (groups.length > 2) _SeeMore(onTap: () => onSeeMore(3)),
        ],
      ],
    );
  }
}
