import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../business/data/availability_models.dart';
import '../../business/data/product_models.dart';
import '../../business/data/rate_models.dart';
import '../../home/data/home_models.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../../messages/presentation/chat_screen.dart';
import '../../bookings/presentation/booking_request_screen.dart';
import '../../orders/data/cart.dart';
import '../../orders/presentation/cart_review_screen.dart';
import '../data/sp_detail_models.dart';
import '../discovery_repository.dart';
import 'widgets/discover_cards.dart';

/// Full service-provider profile. Opened by tapping any SP card.
class ServiceProviderDetailScreen extends ConsumerWidget {
  const ServiceProviderDetailScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(serviceProviderDetailProvider(id));
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _ErrorView(onRetry: () => ref.invalidate(serviceProviderDetailProvider(id))),
        data: (sp) => Stack(
          children: [
            RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async => ref.invalidate(serviceProviderDetailProvider(id)),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  _TopBar(),
                  _ProfileHeader(sp: sp),
                  _Band(child: _AboutBlock(sp: sp)),
                  if (sp.willingToTravel || (sp.hasDateBooking && sp.availability != null) || sp.yearsOfExperience != null || sp.locationLabel != null)
                    _Band(color: AppColors.surface, child: _AvailabilityBlock(sp: sp)),
                  // Charges — shown only for non-menu SPs that have published rates.
                  if (!sp.hasMenu && sp.rates.isNotEmpty) _Band(child: _ChargesBlock(rates: sp.rates)),
                  // Menu — shown only for SPs whose subcategory type == 'menu'.
                  if (sp.hasMenu && sp.products.isNotEmpty)
                    _MenuBlock(products: sp.products, spId: sp.id, spName: sp.name),
                  if (sp.gallery.isNotEmpty) _GalleryBlock(urls: sp.gallery),
                  _Band(child: _ReviewsBlock(sp: sp)),
                  _SubmitReview(id: id),
                  if (sp.events.isNotEmpty) _EventsBlock(events: sp.events),
                  if (sp.posts.isNotEmpty) _PostsBlock(posts: sp.posts),
                  if (sp.groups.isNotEmpty) _Band(child: _GroupsBlock(groups: sp.groups)),
                ],
              ),
            ),
            if (sp.hasDateBooking && !sp.hasMenu) _BookBar(sp: sp),
            if (sp.hasMenu) _CartBar(spId: sp.id),
          ],
        ),
      ),
    );
  }
}

// ── Layout helpers ───────────────────────────────────────────
class _Band extends StatelessWidget {
  const _Band({required this.child, this.color = const Color(0xFFF3F6F3)});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: color,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: child,
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19, color: AppColors.ink)),
            ),
            ?trailing,
          ],
        ),
      );
}

// ── Top bar (back + more) ────────────────────────────────────
class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, topPad + 6, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 30, color: AppColors.ink),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: AppColors.ink),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

// ── Profile header ───────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.sp});
  final ServiceProviderDetail sp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(name: sp.name, photoUrl: sp.photoUrl, radius: 42),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(sp.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 22, color: AppColors.ink)),
                        ),
                        RatingBadge(value: sp.ratingAvg),
                      ],
                    ),
                    if (sp.service != null) ...[
                      const SizedBox(height: 4),
                      Text(sp.service!,
                          style: const TextStyle(
                              color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 14)),
                    ],
                    if (sp.locationLabel != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(sp.locationLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text('For any inquiry, contact here:',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const Spacer(),
              if (sp.userId != null)
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      otherUserId: sp.userId!,
                      otherName: sp.name,
                      otherPhoto: sp.photoUrl,
                      messageType: 'enquiry',
                      entityType: 'sp_profile',
                      entityId: sp.id,
                    ),
                  )),
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(120, 42),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  label: const Text('Message', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── About / Education / Profession ───────────────────────────
class _AboutBlock extends StatelessWidget {
  const _AboutBlock({required this.sp});
  final ServiceProviderDetail sp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('About Me'),
        Text(
          sp.aboutMe?.isNotEmpty == true ? sp.aboutMe! : 'No description added yet.',
          style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
        ),
        if (sp.educations.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('Education', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          const SizedBox(height: 6),
          ...sp.educations.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  e.institution != null ? '${e.label} · ${e.institution}' : e.label,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                ),
              )),
        ],
        if (sp.professions.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('Profession', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          const SizedBox(height: 6),
          ...sp.professions.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(p.label, style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
              )),
        ],
      ],
    );
  }
}

// ── Availability & Travel ────────────────────────────────────
class _AvailabilityBlock extends StatelessWidget {
  const _AvailabilityBlock({required this.sp});
  final ServiceProviderDetail sp;

  @override
  Widget build(BuildContext context) {
    final a = sp.availability;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Availability & Travel'),
        if (sp.willingToTravel) _check('Willing to Travel'),
        if (a?.maxTravelKm != null) _check('Travels up to ${a!.maxTravelKm!.toStringAsFixed(0)} km'),
        if (sp.yearsOfExperience != null) _check('${sp.yearsOfExperience}+ years of experience'),
        if (sp.hasDateBooking && a != null) ...[
          const SizedBox(height: 12),
          _scheduleCard(context, a),
        ],
        if (sp.locationLabel != null) ...[
          const SizedBox(height: 12),
          const Text('Service Area',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(sp.locationLabel!,
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _scheduleCard(BuildContext context, SpAvailability a) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Schedule',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text('${a.daysLabel} · ${a.timeLabel}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                backgroundColor: AppColors.surface,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _SlotsSheet(spId: sp.id),
              ),
              child: const Text('View slots'),
            ),
          ],
        ),
      );

  Widget _check(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary))),
          ],
        ),
      );
}

/// Bottom sheet listing an SP's open bookable slots (view-only; booking happens at checkout).
class _SlotsSheet extends ConsumerWidget {
  const _SlotsSheet({required this.spId});
  final int spId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(spSlotsProvider(spId));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Available slots', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 4),
            const Text('Pick a slot at checkout after adding items to your cart.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            const SizedBox(height: 14),
            slots.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (_, _) => const Padding(padding: EdgeInsets.all(24), child: Text('Could not load slots')),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No open slots right now.', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                final byDay = <String, List<OpenSlot>>{};
                for (final s in list) {
                  byDay.putIfAbsent(s.dayLabel, () => []).add(s);
                }
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: ListView(
                    shrinkWrap: true,
                    children: byDay.entries.map((e) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 6),
                            child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: e.value
                                .map((s) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primarySurface,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(s.timeLabel,
                                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12.5)),
                                    ))
                                .toList(),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Charges (service SP, buyer view) ─────────────────────────
class _ChargesBlock extends StatelessWidget {
  const _ChargesBlock({required this.rates});
  final List<SpRate> rates;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Charges'),
        ...rates.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, color: AppColors.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(r.typeLabel, style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary))),
                  Text('₹${r.amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ],
              ),
            )),
      ],
    );
  }
}

/// Sticky "Book" bar for service SPs → opens the booking request flow.
class _BookBar extends StatelessWidget {
  const _BookBar({required this.sp});
  final ServiceProviderDetail sp;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => BookingRequestScreen(sp: sp)),
            ),
            child: const Text('Book a session'),
          ),
        ),
      ),
    );
  }
}

// ── Work Gallery ─────────────────────────────────────────────
// ── Menu / products (buyer view) ─────────────────────────────
class _MenuBlock extends ConsumerWidget {
  const _MenuBlock({required this.products, required this.spId, required this.spName});
  final List<SpProduct> products;
  final int spId;
  final String spName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final matchesSp = cart.spProfileId == spId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Menu'),
          ...products.map((p) {
            final qty = matchesSp ? (cart.lines[p.id]?.qty ?? 0) : 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: (p.photoUrl != null && p.photoUrl!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: AppConfig.assetUrl(p.photoUrl!),
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => _ph(),
                          )
                        : _ph(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        if (p.price != null)
                          Text('₹${p.price!.toStringAsFixed(0)}${p.quantityLabel.isNotEmpty ? '  ·  ${p.quantityLabel}' : ''}',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  if (qty == 0)
                    OutlinedButton(
                      onPressed: () => notifier.add(spId, spName, p),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        minimumSize: const Size(70, 34),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('Add'),
                    )
                  else
                    _stepper(qty, () => notifier.setQty(p.id, qty - 1), () => notifier.add(spId, spName, p)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _stepper(int qty, VoidCallback minus, VoidCallback plus) => Container(
        decoration: BoxDecoration(border: Border.all(color: AppColors.primary), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            InkWell(onTap: minus, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.remove, size: 16, color: AppColors.primary))),
            SizedBox(width: 22, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
            InkWell(onTap: plus, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.add, size: 16, color: AppColors.primary))),
          ],
        ),
      );

  Widget _ph() => Container(
        width: 56,
        height: 56,
        color: AppColors.primarySurface,
        child: const Icon(Icons.bakery_dining_outlined, color: AppColors.primary),
      );
}

// ── Sticky cart bar ──────────────────────────────────────────
class _CartBar extends ConsumerWidget {
  const _CartBar({required this.spId});
  final int spId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.spProfileId != spId || cart.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartReviewScreen())),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  children: [
                    Text('${cart.count} item${cart.count == 1 ? '' : 's'}  ·  ₹${cart.subtotal.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    const Spacer(),
                    const Text('View Cart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    const Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryBlock extends StatelessWidget {
  const _GalleryBlock({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 20),
            child: _SectionTitle('Work Gallery'),
          ),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: AppConfig.assetUrl(urls[i]),
                  width: 170,
                  height: 120,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(width: 170, color: AppColors.primarySurface),
                  errorWidget: (_, _, _) => Container(
                    width: 170,
                    color: AppColors.primarySurface,
                    child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Verified Reviews ─────────────────────────────────────────
class _ReviewsBlock extends StatelessWidget {
  const _ReviewsBlock({required this.sp});
  final ServiceProviderDetail sp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Verified Review',
          trailing: sp.reviews.length > 2
              ? const Text('View All >',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13))
              : null,
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Verified Reviews from your area',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ),
        if (sp.reviews.isEmpty)
          const Text('No reviews yet — be the first to review.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted))
        else
          ...sp.reviews.take(3).map((r) => _ReviewTile(review: r)),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final SpReview review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(name: review.raterName, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(review.raterName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                        const SizedBox(width: 8),
                        Text(review.raterTypeLabel,
                            style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      review.review?.isNotEmpty == true ? review.review! : 'Rated ${review.rating}★',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RatingBadge(value: review.rating.toDouble()),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.divider),
        ],
      ),
    );
  }
}

// ── Submit a Review ──────────────────────────────────────────
class _SubmitReview extends ConsumerStatefulWidget {
  const _SubmitReview({required this.id});
  final int id;
  @override
  ConsumerState<_SubmitReview> createState() => _SubmitReviewState();
}

class _SubmitReviewState extends ConsumerState<_SubmitReview> {
  int _stars = 0;
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tap a star to rate first')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(discoveryRepositoryProvider).submitReview(
            widget.id,
            rating: _stars,
            review: _controller.text,
          );
      if (!mounted) return;
      _controller.clear();
      setState(() => _stars = 0);
      ref.invalidate(serviceProviderDetailProvider(widget.id));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your review!')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not submit review')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Band(
      color: const Color(0xFFF3F6F3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Submit a Review'),
          Row(
            children: List.generate(5, (i) {
              final filled = i < _stars;
              return GestureDetector(
                onTap: () => setState(() => _stars = i + 1),
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(filled ? Icons.star_rounded : Icons.star_border_rounded,
                      color: filled ? AppColors.warning : AppColors.textMuted, size: 30),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Share your experience....',
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Submit', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Event(s) ─────────────────────────────────────────────────
class _EventsBlock extends StatelessWidget {
  const _EventsBlock({required this.events});
  final List<SpEvent> events;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 20),
            child: _SectionTitle('Event(s)'),
          ),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _SpEventCard(item: events[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpEventCard extends StatelessWidget {
  const _SpEventCard({required this.item});
  final SpEvent item;

  @override
  Widget build(BuildContext context) {
    final e = item.event;
    final date = e.date != null ? DateFormat('EEE, MMM d').format(e.date!) : '';
    final time = eventTimeRange(e);
    final closed = item.isPast;
    final statusLabel = closed ? 'Closed' : (item.isHosting ? 'Hosting' : 'Attending');
    final statusColor = closed ? AppColors.textMuted : AppColors.primary;
    return Container(
      width: 190,
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
                photoUrl: e.photoUrl,
                fallbackIcon: Icons.celebration_rounded,
                width: double.infinity,
                height: 92,
                radius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(6)),
                  child: Text(statusLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
              Positioned(top: 8, right: 8, child: RatingBadge(value: e.ratingAvg, compact: true)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 4),
                Text(time.isNotEmpty ? '$date | $time' : date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                if (e.location != null && e.location!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(e.location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text('By : ${e.creatorName ?? 'Organizer'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                    ),
                    if (!closed) const JoinButton(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Posts ────────────────────────────────────────────────────
class _PostsBlock extends StatelessWidget {
  const _PostsBlock({required this.posts});
  final List<DiscussionItem> posts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Posts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink)),
            const SizedBox(height: 10),
            ...posts.take(2).map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Avatar(name: p.authorName, photoUrl: p.authorPhoto, radius: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.authorName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const Text('Resident',
                                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(p.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.favorite_border, size: 15, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text('${p.likes}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                )),
            Center(
              child: TextButton(
                onPressed: () {},
                child: const Text('View More',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Interest Groups ──────────────────────────────────────────
class _GroupsBlock extends StatelessWidget {
  const _GroupsBlock({required this.groups});
  final List<SpGroup> groups;

  @override
  Widget build(BuildContext context) {
    final admin = groups.where((g) => g.role == 'admin').toList();
    final member = groups.where((g) => g.role == 'member').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Interest Groups'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (admin.isNotEmpty) Expanded(child: _roleColumn('Admin', admin)),
            if (member.isNotEmpty) Expanded(child: _roleColumn('Member', member)),
          ],
        ),
      ],
    );
  }

  Widget _roleColumn(String label, List<SpGroup> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: items.map((g) => _GroupChip(group: g.group)).toList(),
          ),
        ],
      );
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.group});
  final GroupItem group;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              NetworkThumb(
                photoUrl: group.photoUrl,
                fallbackIcon: Icons.groups_rounded,
                width: 66,
                height: 66,
                radius: BorderRadius.circular(33),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  child: Text('${group.members}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(group.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
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
            const Text("Couldn't load this profile", style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
