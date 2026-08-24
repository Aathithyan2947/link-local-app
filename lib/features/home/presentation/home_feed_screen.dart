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
    final workshopsOverride = ref.watch(workshopsSectionAreaProvider);
    final groupsOverride = ref.watch(groupsSectionAreaProvider);
    final spScopedAsync = spOverride != null ? ref.watch(spSectionScopedProvider(spOverride.areaId)) : null;
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
          final workshopsSection = workshopsScopedAsync?.asData?.value ?? feed.workshops;
          final groupsSection = groupsScopedAsync?.asData?.value ?? feed.groups;
          final visibleSps = _selectedCategory == null
              ? spSection.items.take(3).toList()
              : spSection.items.where((sp) => sp.service == _selectedCategory).toList();
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
                locationLabel: scopeState.overrideAreaLabel ?? feed.city?.label ?? 'Your area',
                onLocationTap: _pickArea,
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
              if (feed.discussions.isNotEmpty) ...[
                _SectionHeader('Community Discussions in', feed.city?.name ?? 'your area'),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Ask questions, share updates, and connect with your community',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
                ...feed.discussions.map((d) => _DiscussionCard(
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
                _GroupsWrap(items: groupsSection.items)
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
    required this.locationLabel,
    required this.onLocationTap,
    this.onProfile,
  });
  final HomeFeed feed;
  final String userName;
  final String scope;
  final ValueChanged<String> onScope;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchSubmit;
  final String locationLabel;
  final VoidCallback onLocationTap;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPad + 14, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onLocationTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: Colors.white, size: 18),
                    const SizedBox(width: 4),
                    Text(locationLabel,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                    const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                child: Container(
                  height: 36,
                  width: 36,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                  child: Consumer(
                    builder: (context, ref, _) {
                      final unread = ref.watch(unreadCountProvider).asData?.value ?? 0;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 20),
                          if (unread > 0)
                            Positioned(
                              top: 6,
                              right: 7,
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
              GestureDetector(
                onTap: onProfile,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 36,
                  width: 36,
                  decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                  child: const Icon(Icons.person, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Discover meaningful Local connections',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 16),
          Row(
            children: [
              _statBox('${feed.stats.members}', 'Members'),
              const SizedBox(width: 10),
              _statBox('${feed.stats.serviceProviders}', 'Service Providers'),
              const SizedBox(width: 10),
              _statBox('${feed.stats.events}', 'Events'),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
            child: Row(
              children: [
                const Icon(Icons.search, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: onSearchSubmit,
                    cursorColor: AppColors.primary,
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
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(4, (i) {
              const scopeValues = ['society', 'lane', 'area', 'city'];
              const labels = ['My Society', 'Lane', 'Area', 'City'];
              final selected = scopeValues[i] == scope;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onScope(scopeValues[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white70),
                    ),
                    child: Text(labels[i],
                        style: TextStyle(
                            color: selected ? AppColors.primary : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white38),
          ),
          child: Column(
            children: [
              Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10.5)),
            ],
          ),
        ),
      );
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
    required this.items,
    required this.selectedCategory,
    required this.onSelect,
    required this.onExploreMore,
  });
  final List<ServiceProviderItem> items;
  final String? selectedCategory;
  final ValueChanged<String> onSelect;
  final VoidCallback onExploreMore;

  @override
  Widget build(BuildContext context) {
    final services = <String>{};
    for (final s in items) {
      if (s.service != null) services.add(s.service!);
    }
    final chips = services.take(2).toList();
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          ...chips.map((c) => _catCard(c, Icons.handyman_outlined,
              selected: c == selectedCategory, onTap: () => onSelect(c))),
          _catCard('Explore\nMore...', Icons.arrow_forward, selected: false, onTap: onExploreMore),
        ],
      ),
    );
  }

  Widget _catCard(String label, IconData icon, {required bool selected, required VoidCallback onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 100,
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySurface : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primary, size: 24),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      );
}

class _SpCard extends StatelessWidget {
  const _SpCard({required this.sp, required this.city});
  final ServiceProviderItem sp;
  final String city;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ServiceProviderDetailScreen(id: sp.id)),
      ),
      child: Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Avatar(name: sp.name, photoUrl: sp.photoUrl, radius: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(sp.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    RatingBadge(value: sp.ratingAvg, compact: true),
                  ],
                ),
                const SizedBox(height: 2),
                Text(sp.service ?? 'Service Provider', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(city, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    const Text('  ·  300m', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ServiceProviderDetailScreen(id: sp.id)),
            ),
            child: const Text('View Profile', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(name: item.authorName, photoUrl: item.authorPhoto, radius: 18),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.authorName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const Text('Resident · 2hr ago', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(item.text, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.favorite_border, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('${item.likes}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(width: 16),
              const Icon(Icons.mode_comment_outlined, size: 17, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('${item.comments} Replies', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
    return SizedBox(
      height: 246,
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
              borderRadius: BorderRadius.circular(16),
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
                      radius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.calendar_today, size: 11, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(time.isNotEmpty ? '$date | $time' : date,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ),
                      ]),
                      if (w.location != null && w.location!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.location_on_outlined, size: 11, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(w.location!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
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

class _GroupsWrap extends StatelessWidget {
  const _GroupsWrap({required this.items});
  final List<GroupItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: items.take(6).map((g) {
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => GroupProfileScreen(id: g.id)),
            ),
            child: Container(
            width: (MediaQuery.of(context).size.width - 40 - 24) / 3,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: const BoxDecoration(color: AppColors.primarySurface, shape: BoxShape.circle),
                  child: const Icon(Icons.groups_rounded, color: AppColors.primary),
                ),
                const SizedBox(height: 8),
                Text(g.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${g.members} Members', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
          );
        }).toList(),
      ),
    );
  }
}

class _ReferralBanner extends StatelessWidget {
  const _ReferralBanner({required this.info});
  final ReferralInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 0, 18),
      decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.message.isEmpty ? 'Earn ₹150 for every friend you refer' : info.message,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 6),
                const Text('Get ₹150 as soon as they make their first booking',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size(120, 40),
                    elevation: 0,
                  ),
                  child: const Text('Refer Now'),
                ),
              ],
            ),
          ),
          Image.asset('assets/images/referral_gift.png', width: 96, fit: BoxFit.contain),
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
class _DocReminderBanner extends ConsumerWidget {
  const _DocReminderBanner({required this.rejected});
  final bool rejected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: rejected ? const Color(0xFFFDECEC) : AppColors.primarySurface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddressProofScreen()),
            );
            ref.invalidate(myAddressProofProvider);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(rejected ? Icons.error_outline : Icons.verified_user_outlined,
                    color: rejected ? AppColors.error : AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rejected ? 'Address proof rejected' : 'Verify your address',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        rejected
                            ? 'Re-upload a document to get verified.'
                            : 'Upload a document to get verified.',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                  tooltip: 'Skip',
                  onPressed: () => dismissDocReminder(ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
