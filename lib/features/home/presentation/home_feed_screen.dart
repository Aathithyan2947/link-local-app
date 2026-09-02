import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../address/data/address_repository.dart';
import '../../address/presentation/address_proof_screen.dart';
import '../../auth/application/auth_controller.dart';
import '../../discovery/discovery_repository.dart';
import '../../discovery/presentation/event_detail_screen.dart';
import '../../discovery/presentation/group_profile_screen.dart';
import '../../discovery/presentation/service_provider_detail_screen.dart';
import '../../feed/presentation/feed_screen.dart';
import '../../feed/presentation/post_detail_screen.dart';
import '../../discovery/presentation/widgets/discover_cards.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../profile/data/profile_repository.dart';
import '../../business/data/business_repository.dart';
import '../../services/data/service_profile_repository.dart';
import '../../services/presentation/category_fields_form_screen.dart';
import '../data/doc_reminder.dart';
import '../data/profile_congrats.dart';
import '../data/home_models.dart';
import '../data/home_repository.dart';
import 'widgets/area_picker_sheet.dart';
import 'widgets/home_widgets.dart';
import 'widgets/service_icons.dart';

/// The SP's home-banner-relevant fields — Basic Details + Travel + (menu SPs only) Service
/// Type + Delivery, EXCLUDING Payment and anything else (gallery/education/profession/
/// contacts/address verification). Deliberately stricter-scoped than the backend's
/// completionPercent, which this does not replace. Judged by [isOnboardingComplete].
List<CustomField> _bannerFields(List<CustomField> fields, {required bool hasMenu}) =>
    onboardingRelevantFields(fields, hasMenu: hasMenu, excluding: const {'payment'});

class HomeFeedScreen extends ConsumerStatefulWidget {
  const HomeFeedScreen({super.key, this.onProfile, this.onOpenDiscover});

  /// Opens the profile screen (wired to the header avatar).
  final VoidCallback? onProfile;

  /// Switches to the Discover surface on a given tab (0=All 1=Events 2=Service Providers
  /// 3=Groups) — wired to `HomeShell._openDiscover` so Home and Discover share one Navigator
  /// stack instead of pushing a redundant second Discover screen.
  final ValueChanged<int>? onOpenDiscover;

  @override
  ConsumerState<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends ConsumerState<HomeFeedScreen> {
  late final TextEditingController _searchCtrl;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _goToDiscover(int tab) => widget.onOpenDiscover?.call(tab);

  void _submitSearch(String text) {
    final q = text.trim();
    if (q.isEmpty) return;
    ref.read(discoverQueryProvider.notifier).set(q);
    _goToDiscover(0); // 0 = "All" tab — filters Events/SPs/Groups together
  }

  /// Clears the field AND the Discover query it feeds, so tapping the X actually resets
  /// results rather than leaving a stale filter behind on the Discover surface.
  void _clearSearch() {
    _searchCtrl.clear();
    ref.read(discoverQueryProvider.notifier).set('');
  }

  /// The Members counter — the community feed is where neighbours actually surface; the app
  /// has no standalone member directory to send them to.
  void _openMembers() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedScreen()));

  void _toggleCategory(String c) => setState(() => _selectedCategory = _selectedCategory == c ? null : c);

  Future<void> _pickArea() async {
    final cityId = ref.read(myProfileProvider).asData?.value.cityId;
    final picked = await showAreaPickerSheet(context, cityId: cityId);
    if (picked != null) ref.read(homeScopeProvider.notifier).setArea(picked.id, picked.areaName);
  }

  /// Per-section pickers — unlike [_pickArea] (whole-feed scope), these only re-fetch the
  /// one section whose header dropdown was tapped.
  Future<void> _pickSectionArea(NotifierProvider<SectionAreaNotifier, SectionAreaOverride?> provider) async {
    final cityId = ref.read(myProfileProvider).asData?.value.cityId;
    final picked = await showAreaPickerSheet(context, cityId: cityId);
    if (picked != null) ref.read(provider.notifier).set(picked.id, picked.areaName);
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(homeFeedProvider);
    final user = ref.watch(authControllerProvider).user;
    final scopeState = ref.watch(homeScopeProvider);

    // Per-section area overrides (Service Providers/Workshops/Groups headers) — independent
    // of `scopeState`, which only drives the top banner + My Society/Lane/Area/City chips.
    final spOverride = ref.watch(spSectionAreaProvider);
    final discussionsOverride = ref.watch(discussionsSectionAreaProvider);
    final workshopsOverride = ref.watch(workshopsSectionAreaProvider);
    final groupsOverride = ref.watch(groupsSectionAreaProvider);
    final spScopedAsync = spOverride != null ? ref.watch(spSectionScopedProvider(spOverride.areaId)) : null;
    final discussionsScopedAsync =
        discussionsOverride != null ? ref.watch(discussionsSectionScopedProvider(discussionsOverride.areaId)) : null;
    final workshopsScopedAsync =
        workshopsOverride != null ? ref.watch(workshopsSectionScopedProvider(workshopsOverride.areaId)) : null;
    final groupsScopedAsync =
        groupsOverride != null ? ref.watch(groupsSectionScopedProvider(groupsOverride.areaId)) : null;

    // Gentle, dismissible reminder to upload address proof (only when not yet submitted/approved).
    final proof = ref.watch(myAddressProofProvider).asData?.value;
    final reminderDismissed = ref.watch(docReminderDismissedProvider).asData?.value ?? true;
    final showDocReminder = proof != null &&
        proof.hasAddress &&
        !reminderDismissed &&
        (proof.status == 'none' || proof.status == 'rejected');

    // "Complete your profile" prompt for SPs whose PRIMARY onboarding flow isn't filled in
    // yet; once complete, a one-time congrats banner takes its place (see profile_congrats.dart).
    final customFields = ref.watch(customFieldsProvider).asData?.value;
    final hasMenu = ref.watch(myProviderFeaturesProvider).asData?.value.hasMenu ?? false;
    final myProfile = ref.watch(myProfileProvider).asData?.value;
    final bannerFields = customFields == null ? null : _bannerFields(customFields, hasMenu: hasMenu);
    // Completion is what the SP actually did — pressing Confirm on the last onboarding step —
    // not a guess from which fields are filled. Inference couldn't see the Products step at
    // all (it has no admin fields), so a menu SP who never added an item read as finished.
    final finishedOnboarding = myProfile?.hasFinishedOnboarding ?? false;
    // Still nag if a required field is unanswered — an admin can add one after the fact.
    final missingRequired = bannerFields != null && hasUnansweredRequiredField(bannerFields);
    final congratsShown = ref.watch(profileCongratsShownProvider).asData?.value ?? true;

    final isSp = user?.isServiceProvider == true;
    final showProfileBanner = isSp && myProfile != null && (!finishedOnboarding || missingRequired);
    // One-time, and only once they've been all the way through.
    final showCongratsBanner = isSp && finishedOnboarding && !missingRequired && !congratsShown;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(message: '$e', onRetry: () => ref.invalidate(homeFeedProvider)),
        data: (feed) {
          // Each section falls back to the default feed slice when it has no override, or
          // while its scoped fetch is still in flight — avoids a loading flicker by keeping
          // the previous content visible until the new area's data arrives.
          final spSection = spScopedAsync?.asData?.value ?? feed.serviceProviders;
          // Home shows at most 3 discussions; the rest live behind "See all discussions".
          final discussions = (discussionsScopedAsync?.asData?.value ?? feed.discussions).take(3).toList();
          final workshopsSection = workshopsScopedAsync?.asData?.value ?? feed.workshops;
          final groupsSection = groupsScopedAsync?.asData?.value ?? feed.groups;
          // Matches on every service a provider offers, not just the one shown on their card —
          // the shortcut's badge counts all of them, so filtering on the primary alone made
          // the list come up short of its own badge.
          final visibleSps = _selectedCategory == null
              ? spSection.items.take(3).toList()
              : spSection.items.where((sp) => sp.services.contains(_selectedCategory)).toList();
          return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => ref.refresh(homeFeedProvider.future),
          child: ListView(
            padding: EdgeInsets.only(bottom: 66 + MediaQuery.of(context).padding.bottom + 24),
            children: [
              _Header(
                feed: feed,
                userName: user?.name ?? 'there',
                scope: scopeState.scope,
                onScope: (s) => ref.read(homeScopeProvider.notifier).setScope(s),
                onProfile: widget.onProfile,
                searchController: _searchCtrl,
                onSearchSubmit: _submitSearch,
                onSearchClear: _clearSearch,
                locationLabel: scopeState.overrideAreaLabel ?? feed.city?.label ?? 'Your area',
                onLocationTap: _pickArea,
                onMembers: _openMembers,
                onServiceProviders: () => _goToDiscover(2),
                onEvents: () => _goToDiscover(1),
              ),
              const SizedBox(height: 8),
              if (showProfileBanner)
                const _ProfileCompletionBanner()
              else if (showCongratsBanner)
                const _ProfileCongratsBanner(),
              if (showDocReminder) _DocReminderBanner(rejected: proof.status == 'rejected'),
              _SectionHeader('Service provider in', '${spOverride?.label ?? feed.city?.name ?? ''}(${spSection.total})',
                  dropdown: true, onTap: () => _pickSectionArea(spSectionAreaProvider)),
              if (spSection.items.isNotEmpty) ...[
                _ServiceCategoryRow(
                  services: feed.spServices,
                  items: spSection.items,
                  selectedCategory: _selectedCategory,
                  onSelect: _toggleCategory,
                  onExploreMore: () => _goToDiscover(2),
                ),
                const SizedBox(height: 12),
                ...visibleSps.map((sp) => _SpCard(sp: sp, city: feed.city?.name ?? '')),
              ] else
                _EmptyScopedSection(
                  label: 'No service providers in ${spOverride?.label ?? feed.city?.name ?? 'this area'} yet.',
                ),
              if (discussions.isNotEmpty) ...[
                _SectionHeader('Community Discussions in',
                    discussionsOverride?.label ?? feed.city?.name ?? 'your area',
                    dropdown: true, onTap: () => _pickSectionArea(discussionsSectionAreaProvider)),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Ask questions, share updates, and connect with your community',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
                ...discussions.map((d) => _DiscussionCard(
                      item: d,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PostDetailScreen(id: d.id)),
                      ),
                    )),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FeedScreen()),
                    ),
                    child: const Text('See all discussions',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
              ],
              _SectionHeader('Workshops in', '${workshopsOverride?.label ?? feed.city?.name ?? ''}(${workshopsSection.total})',
                  dropdown: true, onTap: () => _pickSectionArea(workshopsSectionAreaProvider)),
              if (workshopsSection.items.isNotEmpty)
                _WorkshopRow(items: workshopsSection.items)
              else
                _EmptyScopedSection(
                  label: 'No workshops in ${workshopsOverride?.label ?? feed.city?.name ?? 'this area'} yet.',
                ),
              _SectionHeader('Groups in', '${groupsOverride?.label ?? feed.city?.name ?? ''}(${groupsSection.total})',
                  dropdown: true, onTap: () => _pickSectionArea(groupsSectionAreaProvider)),
              if (groupsSection.items.isNotEmpty)
                _GroupsRow(items: groupsSection.items)
              else
                _EmptyScopedSection(
                  label: 'No groups in ${groupsOverride?.label ?? feed.city?.name ?? 'this area'} yet.',
                ),
              _ReferralBanner(info: feed.referral),
            ],
          ),
          );
        },
      ),
    );
  }
}

// ── Green header ─────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({
    required this.feed,
    required this.userName,
    required this.scope,
    required this.onScope,
    required this.searchController,
    required this.onSearchSubmit,
    required this.onSearchClear,
    required this.locationLabel,
    required this.onLocationTap,
    required this.onMembers,
    required this.onServiceProviders,
    required this.onEvents,
    this.onProfile,
  });
  final HomeFeed feed;
  final String userName;
  final String scope;
  final ValueChanged<String> onScope;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchSubmit;
  final VoidCallback onSearchClear;
  final String locationLabel;
  final VoidCallback onLocationTap;
  final VoidCallback onMembers;
  final VoidCallback onServiceProviders;
  final VoidCallback onEvents;
  final VoidCallback? onProfile;

  static const List<String> _scopeValues = ['society', 'lane', 'area', 'city'];
  static const List<String> _scopeLabels = ['My Society', 'Lane', 'Area', 'City'];

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Expanded (not Flexible + Spacer): those split the free space evenly, which
              // clipped "Mumbai, Maharashtra" to "Mumbai, M…" with room to spare.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onLocationTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, color: Colors.white, size: 18),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(locationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ),
              // Bare glyphs, per Figma — the translucent circular chips these used to sit in
              // read as buttons competing with the location control next to them.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Consumer(
                    builder: (context, ref, _) {
                      final unread = ref.watch(unreadCountProvider).asData?.value ?? 0;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.notifications, color: Colors.white, size: 26),
                          if (unread > 0)
                            Positioned(
                              top: 1,
                              right: 2,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.primary, width: 1.5),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onProfile,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Icon(Icons.person, color: Colors.white, size: 26),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // One line, always: FittedBox shrinks the headline on narrow handsets rather than
          // letting it wrap to two, which is what the design flagged.
          const SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                'Discover meaningful Local connections',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatBox(value: '${feed.stats.members}', label: 'Members', onTap: onMembers),
              const SizedBox(width: 10),
              _StatBox(
                  value: '${feed.stats.serviceProviders}',
                  label: 'Service Providers',
                  onTap: onServiceProviders),
              const SizedBox(width: 10),
              _StatBox(value: '${feed.stats.events}', label: 'Events', onTap: onEvents),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(left: 14, right: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.search, color: AppColors.textMuted, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: onSearchSubmit,
                    cursorColor: AppColors.primary,
                    style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Just Moved in, need help with "Cleaning"',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ),
                ),
                // Listens to the controller directly so the clear affordance appears without
                // rebuilding (and re-fetching) the whole feed on every keystroke.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: searchController,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox(width: 8)
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onSearchClear,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_scopeValues.length, (i) {
              final value = _scopeValues[i];
              return _ScopeTab(
                label: _scopeLabels[i],
                count: feed.scopeCounts?.of(value),
                selected: value == scope,
                onTap: () => onScope(value),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// One of the three header counters. Each opens the surface it counts.
class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label, required this.onTap});
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white38),
            ),
            child: Column(
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20, height: 1.2)),
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.25)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// My Society / Lane / Area / City — underlined text tabs carrying the number of results
/// each scope would surface, rather than the bordered pills they replace.
class _ScopeTab extends StatelessWidget {
  const _ScopeTab({required this.label, required this.count, required this.selected, required this.onTap});
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: selected ? Colors.white : Colors.transparent, width: 2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white.withValues(alpha: 0.8),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                )),
            if (count != null) ...[
              const SizedBox(width: 5),
              Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryDeep,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text('$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, height: 1.3)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Section header ───────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.highlight, {this.dropdown = false, this.onTap});
  final String title;
  final String highlight;
  final bool dropdown;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Flexible(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 17),
              children: [
                TextSpan(text: '$title '),
                TextSpan(text: highlight, style: const TextStyle(color: AppColors.primary)),
              ],
            ),
          ),
        ),
        if (dropdown) ...[
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 22),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: onTap == null ? row : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row),
    );
  }
}

/// Shown under a scoped section's header instead of letting the whole section (header +
/// area dropdown included) disappear when the picked area has no data — keeps the dropdown
/// reachable so the member can just pick a different area.
class _EmptyScopedSection extends StatelessWidget {
  const _EmptyScopedSection({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Text('$label Try a different area from the dropdown above.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      );
}

// ── Service provider category shortcuts ──────────────────────
class _ServiceCategoryRow extends StatelessWidget {
  const _ServiceCategoryRow({
    required this.services,
    required this.items,
    required this.selectedCategory,
    required this.onSelect,
    required this.onExploreMore,
  });

  /// Server-counted services in scope. Empty on older backends, in which case the row
  /// falls back to whatever services the returned providers happen to name.
  final List<ServiceCount> services;
  final List<ServiceProviderItem> items;
  final String? selectedCategory;
  final ValueChanged<String> onSelect;
  final VoidCallback onExploreMore;

  List<ServiceCount> get _cards {
    if (services.isNotEmpty) return services.take(3).toList();
    final seen = <String>{};
    for (final s in items) {
      if (s.service != null) seen.add(s.service!);
    }
    return seen.take(3).map((n) => ServiceCount(name: n, count: 0)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        clipBehavior: Clip.none,
        children: [
          ..._cards.map((c) => _CategoryCard(
                label: c.name,
                count: c.count,
                selected: c.name == selectedCategory,
                onTap: () => onSelect(c.name),
              )),
          _CategoryCard(label: 'Explore\nMore...', count: 0, selected: false, onTap: onExploreMore),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  /// "Explore More..." is the row's tail action, not a service — the design gives it the
  /// same card but no icon, so its label sits centred on its own.
  bool get _isExploreMore => label.startsWith('Explore');

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 86,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.primarySurface : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? AppColors.primary : AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!_isExploreMore) ...[
            ServiceIcon(serviceName: label, size: 30, color: AppColors.textPrimary),
            const SizedBox(height: 8),
          ],
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: AppColors.textPrimary,
              )),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            card,
            if (count > 0)
              Positioned(
                top: -6,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: AppColors.background, width: 1.5),
                  ),
                  child: Text('$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, height: 1.3)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpCard extends StatelessWidget {
  const _SpCard({required this.sp, required this.city});
  final ServiceProviderItem sp;
  final String city;

  @override
  Widget build(BuildContext context) {
    void open() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ServiceProviderDetailScreen(id: sp.id)),
        );

    return GestureDetector(
      onTap: open,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(name: sp.name, photoUrl: sp.photoUrl, radius: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(sp.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                      const SizedBox(width: 8),
                      RatingBadge(value: sp.ratingAvg, compact: true),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(sp.service ?? 'Service Provider',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 6),
                  // Location and the CTA share the last line — "View Profile" was previously
                  // a full-height column of its own, which left it floating beside the card.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text('$city | 300m',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: open,
                        child: const Text('View Profile',
                            style: TextStyle(
                                color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscussionCard extends StatelessWidget {
  const _DiscussionCard({required this.item, this.onTap});
  final DiscussionItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                Avatar(name: item.authorName, photoUrl: item.authorPhoto, radius: 21),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                      const SizedBox(height: 1),
                      const Text('Resident  •  2hr ago',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(item.text,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.35)),
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.thumb_up_alt_outlined, size: 17, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('${item.likes}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(width: 18),
                const Icon(Icons.mode_comment_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('${item.comments} Replies',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkshopRow extends StatelessWidget {
  const _WorkshopRow({required this.items});
  final List<WorkshopItem> items;

  @override
  Widget build(BuildContext context) {
    // A horizontal list needs a fixed height, so it has to match the tallest card exactly or
    // every tile carries the difference as dead space under its Join row. The venue line is
    // the only optional part, so its presence is the whole variance.
    final hasLocation = items.any((w) => (w.location ?? '').isNotEmpty);
    return SizedBox(
      height: hasLocation ? 214 : 194,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final w = items[i];
          final date = w.date != null ? DateFormat('EEE, MMM d').format(w.date!) : '';
          final time = eventTimeRange(w);
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EventDetailScreen(id: w.id)),
            ),
            child: Container(
            width: 212,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    NetworkThumb(
                      photoUrl: w.photoUrl,
                      fallbackIcon: Icons.celebration_rounded,
                      width: double.infinity,
                      height: 96,
                      radius: const BorderRadius.vertical(top: Radius.circular(9)),
                    ),
                    Positioned(top: 8, right: 8, child: RatingBadge(value: w.ratingAvg, compact: true)),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.calendar_today, size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(time.isNotEmpty ? '$date | $time' : date,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                        ),
                      ]),
                      if (w.location != null && w.location!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(w.location!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary))),
                        ]),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text('By : ${w.creatorName ?? 'Organizer'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                          ),
                          const SizedBox(width: 6),
                          const JoinButton(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          );
        },
      ),
    );
  }
}

/// Groups as a scrolling row of circular tiles with a member-count badge, per the design —
/// replaces the three-across grid of bordered cards, which gave each group a card's worth of
/// visual weight in a section meant to be scanned.
class _GroupsRow extends StatelessWidget {
  const _GroupsRow({required this.items});
  final List<GroupItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final g = items[i];
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => GroupProfileScreen(id: g.id)),
            ),
            child: SizedBox(
              width: 68,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 58,
                        width: 58,
                        decoration: const BoxDecoration(color: AppColors.border, shape: BoxShape.circle),
                        clipBehavior: Clip.antiAlias,
                        child: g.photoUrl != null && g.photoUrl!.isNotEmpty
                            ? NetworkThumb(
                                photoUrl: g.photoUrl,
                                fallbackIcon: Icons.groups_rounded,
                                width: 58,
                                height: 58,
                                radius: BorderRadius.circular(29),
                              )
                            : const Icon(Icons.groups_rounded, color: AppColors.textSecondary, size: 26),
                      ),
                      if (g.members > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.background, width: 1.5),
                            ),
                            child: Text('${g.members}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(g.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, height: 1.25, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Light card with a dark CTA, per the design — the solid green gradient it replaces put the
/// banner at the same visual weight as the header and read as a second app bar.
class _ReferralBanner extends StatelessWidget {
  const _ReferralBanner({required this.info});
  final ReferralInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(info.message.isEmpty ? 'Earn ₹150 for every friend you refer' : info.message,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15, height: 1.25)),
                  const SizedBox(height: 5),
                  const Text('Get ₹150 as soon as they make their first booking',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.3)),
                  const SizedBox(height: 12),
                  Material(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {},
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 15),
                            SizedBox(width: 6),
                            Text('Refer Now',
                                style: TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Image.asset('assets/images/referral_gift.png', width: 108, fit: BoxFit.contain),
        ],
      ),
    );
  }
}

// ── "Complete your profile" hero prompt (SPs only, until fully filled in) ────
class _ProfileCompletionBanner extends ConsumerWidget {
  const _ProfileCompletionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final fields = await ref.read(serviceProfileRepositoryProvider).getCustomFields();
        var hasMenu = false;
        try {
          hasMenu = (await ref.read(businessRepositoryProvider).myProviderFeatures()).hasMenu;
        } catch (_) {}
        final cats = onboardingCategories(fields, hasMenu: hasMenu);
        if (cats.isEmpty || !context.mounted) return;
        await pushOnboardingStep(context, ref, cats);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFFF7E0), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Expanded(
              child: Text('Complete your profile and let neighbours find you',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: AppColors.ink)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.ink),
          ],
        ),
      ),
    );
  }
}

// ── One-time "profile complete" congratulations banner (auto-dismisses after 10s) ───
class _ProfileCongratsBanner extends ConsumerStatefulWidget {
  const _ProfileCongratsBanner();

  @override
  ConsumerState<_ProfileCongratsBanner> createState() => _ProfileCongratsBannerState();
}

class _ProfileCongratsBannerState extends ConsumerState<_ProfileCongratsBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 10), () => markProfileCongratsShown(ref));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(14)),
      child: const Row(
        children: [
          Icon(Icons.celebration_rounded, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text('Your profile is complete! Neighbours can now find you.',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: AppColors.ink)),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ── Dismissible "upload your address proof" reminder ─────────
/// Styled as the design's warning strip — a full-width amber bar with a red alert glyph —
/// rather than the soft green card it used to be, which read as a tip instead of a to-do.
class _DocReminderBanner extends ConsumerWidget {
  const _DocReminderBanner({required this.rejected});
  final bool rejected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Material(
        color: rejected ? const Color(0xFFFDECEC) : const Color(0xFFFDF6DD),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddressProofScreen()),
            );
            ref.invalidate(myAddressProofProvider);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.error, color: AppColors.error, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rejected ? 'Address proof rejected — re-upload' : 'Upload your address proof',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textPrimary, size: 22),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => dismissDocReminder(ref),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.close, size: 16, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
