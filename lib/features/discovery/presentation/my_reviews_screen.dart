import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../data/my_activity_models.dart';
import '../discovery_repository.dart';
import 'event_detail_screen.dart';
import 'group_profile_screen.dart';
import 'service_provider_detail_screen.dart';
import 'widgets/discover_cards.dart';

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}hr ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d').format(dt);
}

/// Every review the current user has submitted — on service providers, events, and
/// groups. Reached from Profile → Personal → Reviews.
class MyReviewsScreen extends ConsumerStatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  ConsumerState<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends ConsumerState<MyReviewsScreen> {
  bool _spExpanded = false;
  bool _eventsExpanded = false;
  bool _groupsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myReviewsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Submitted Reviews'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: OutlinedButton(onPressed: () => ref.invalidate(myReviewsProvider), child: const Text('Retry'))),
        data: (reviews) {
          if (reviews.serviceProviders.isEmpty && reviews.events.isEmpty && reviews.groups.isEmpty) {
            return const Center(child: Text('No reviews submitted yet.'));
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => ref.refresh(myReviewsProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Section(
                  title: 'Service Providers',
                  items: reviews.serviceProviders,
                  expanded: _spExpanded,
                  onSeeMore: () => setState(() => _spExpanded = true),
                  circular: true,
                  fallbackIcon: Icons.person,
                  onTap: (id) => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ServiceProviderDetailScreen(id: id))),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Events',
                  items: reviews.events,
                  expanded: _eventsExpanded,
                  onSeeMore: () => setState(() => _eventsExpanded = true),
                  circular: false,
                  fallbackIcon: Icons.celebration_rounded,
                  onTap: (id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(id: id))),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Groups',
                  items: reviews.groups,
                  expanded: _groupsExpanded,
                  onSeeMore: () => setState(() => _groupsExpanded = true),
                  circular: true,
                  fallbackIcon: Icons.groups_rounded,
                  onTap: (id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupProfileScreen(id: id))),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.expanded,
    required this.onSeeMore,
    required this.circular,
    required this.fallbackIcon,
    required this.onTap,
  });
  final String title;
  final List<SubmittedReview> items;
  final bool expanded;
  final VoidCallback onSeeMore;
  final bool circular;
  final IconData fallbackIcon;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
        const SizedBox(height: 10),
        if (items.isEmpty) const Text('No reviews here yet.', style: TextStyle(color: AppColors.textMuted)),
        for (final r in expanded ? items : items.take(2).toList()) ...[
          _ReviewRow(review: r, circular: circular, fallbackIcon: fallbackIcon, onTap: () => onTap(r.entityId)),
          const SizedBox(height: 10),
        ],
        if (!expanded && items.length > 2) Center(child: TextButton(onPressed: onSeeMore, child: const Text('See More'))),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review, required this.circular, required this.fallbackIcon, required this.onTap});
  final SubmittedReview review;
  final bool circular;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NetworkThumb(
                photoUrl: review.photoUrl,
                fallbackIcon: fallbackIcon,
                width: 48,
                height: 48,
                radius: BorderRadius.circular(circular ? 24 : 10),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(review.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.ink)),
                        ),
                        const SizedBox(width: 8),
                        RatingBadge(value: review.rating.toDouble(), compact: true),
                      ],
                    ),
                    if (review.role != null && review.role!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(review.role!, style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ],
                    if (review.subtitle != null && review.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(review.subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                    if (review.address != null && review.address!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(review.address!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ],
                    if (review.review != null && review.review!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(review.review!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    ],
                    if (review.createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(_timeAgo(review.createdAt!), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
