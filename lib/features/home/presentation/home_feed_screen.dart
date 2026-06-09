import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../data/home_models.dart';
import '../data/home_repository.dart';
import 'widgets/home_widgets.dart';

class HomeFeedScreen extends ConsumerStatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  ConsumerState<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends ConsumerState<HomeFeedScreen> {
  int _scope = 3; // My Society | Lane | Area | City  (City default)

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(homeFeedProvider);
    final user = ref.watch(authControllerProvider).user;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(message: '$e', onRetry: () => ref.invalidate(homeFeedProvider)),
        data: (feed) => RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(homeFeedProvider),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _Header(
                feed: feed,
                userName: user?.name ?? 'there',
                scope: _scope,
                onScope: (i) => setState(() => _scope = i),
              ),
              const SizedBox(height: 8),
              if (feed.serviceProviders.items.isNotEmpty) ...[
                _SectionHeader('Service provider in', '${feed.city?.name ?? ''}(${feed.serviceProviders.total})'),
                _ServiceCategoryRow(items: feed.serviceProviders.items),
                ...feed.serviceProviders.items.take(3).map((sp) => _SpCard(sp: sp, city: feed.city?.name ?? '')),
              ],
              _SectionHeader('Community Discussions in', feed.city?.name ?? 'your area'),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Ask questions, share updates, and connect with your community',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
              ...feed.discussions.map((d) => _DiscussionCard(item: d)),
              if (feed.workshops.items.isNotEmpty) ...[
                _SectionHeader('Workshops in', '${feed.city?.name ?? ''}(${feed.workshops.total})'),
                _WorkshopRow(items: feed.workshops.items),
              ],
              if (feed.groups.items.isNotEmpty) ...[
                _SectionHeader('Groups in', '${feed.city?.name ?? ''}(${feed.groups.total})'),
                _GroupsWrap(items: feed.groups.items),
              ],
              _ReferralBanner(info: feed.referral),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Green header ─────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.feed, required this.userName, required this.scope, required this.onScope});
  final HomeFeed feed;
  final String userName;
  final int scope;
  final ValueChanged<int> onScope;

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
              const Icon(Icons.location_on, color: Colors.white, size: 18),
              const SizedBox(width: 4),
              Text(feed.city?.label ?? 'Your area',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
              const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
              const Spacer(),
              Container(
                height: 36,
                width: 36,
                decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                child: const Icon(Icons.person, color: Colors.white, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Discover meaningful Local connections',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat('${feed.stats.members}', 'Members'),
              _divider(),
              _stat('${feed.stats.serviceProviders}', 'Service Providers'),
              _divider(),
              _stat('${feed.stats.events}', 'Events'),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
            child: const Row(
              children: [
                Icon(Icons.search, color: AppColors.textMuted),
                SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search people, services, events...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(4, (i) {
              const labels = ['My Society', 'Lane', 'Area', 'City'];
              final selected = i == scope;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onScope(i),
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

  Widget _stat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      );

  Widget _divider() => Container(height: 32, width: 1, color: Colors.white24);
}

// ── Section header ───────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.highlight);
  final String title;
  final String highlight;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 17),
          children: [
            TextSpan(text: '$title '),
            TextSpan(text: highlight, style: const TextStyle(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

// ── Service provider category shortcuts ──────────────────────
class _ServiceCategoryRow extends StatelessWidget {
  const _ServiceCategoryRow({required this.items});
  final List<ServiceProviderItem> items;

  @override
  Widget build(BuildContext context) {
    final services = <String>{};
    for (final s in items) {
      if (s.service != null) services.add(s.service!);
    }
    final chips = services.take(3).toList();
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          ...chips.map((c) => _catCard(c, Icons.handyman_outlined)),
          _catCard('Explore\nMore...', Icons.arrow_forward),
        ],
      ),
    );
  }

  Widget _catCard(String label, IconData icon) => Container(
        width: 86,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
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
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

class _SpCard extends StatelessWidget {
  const _SpCard({required this.sp, required this.city});
  final ServiceProviderItem sp;
  final String city;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Colors.white, size: 11),
                          const SizedBox(width: 2),
                          Text(sp.ratingCount > 0 ? '${sp.ratingCount}' : 'New',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
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
            onPressed: () {},
            child: const Text('View Profile', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _DiscussionCard extends StatelessWidget {
  const _DiscussionCard({required this.item});
  final DiscussionItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _WorkshopRow extends StatelessWidget {
  const _WorkshopRow({required this.items});
  final List<WorkshopItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final w = items[i];
          final date = w.date != null ? DateFormat('EEE, MMM d').format(w.date!) : '';
          return Container(
            width: 200,
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
                    Container(
                      height: 96,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: const Icon(Icons.celebration_rounded, color: Colors.white, size: 40),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
                        child: Text(w.isPaid ? 'Paid' : 'Free',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.calendar_today, size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Expanded(child: Text(date, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                      ]),
                      if (w.location != null) ...[
                        const SizedBox(height: 2),
                        Row(children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Expanded(child: Text(w.location!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
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
          return Container(
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
