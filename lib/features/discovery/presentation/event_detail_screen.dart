import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../data/event_detail_models.dart';
import '../discovery_repository.dart';
import 'widgets/discover_cards.dart';

/// Full event detail — the "Workshop details" frame. Join / pay (mock) / rate.
class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  bool _busy = false;
  int _stars = 0;
  final _review = TextEditingController();

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  DiscoveryRepository get _repo => ref.read(discoveryRepositoryProvider);

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(eventDetailProvider(widget.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(EventDetail e) => _run(() async {
        await _repo.joinEvent(e.id);
        if (e.isPaid) await _repo.payForEvent(e.id); // MOCK payment
      }, e.isPaid ? 'Joined — payment successful' : 'You have joined!');

  Future<void> _pay(EventDetail e) => _run(() => _repo.payForEvent(e.id), 'Payment successful');
  Future<void> _withdraw(EventDetail e) => _run(() => _repo.withdrawEvent(e.id), 'You have withdrawn');

  Future<void> _submitReview() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tap a star to rate first')));
      return;
    }
    await _run(() => _repo.rateEvent(widget.id, rating: _stars, review: _review.text), 'Thanks for your review!');
    if (mounted) {
      _review.clear();
      setState(() => _stars = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(eventDetailProvider(widget.id));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _error(),
        data: (e) => RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(eventDetailProvider(widget.id)),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _hero(e),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoCard(e),
                    const SizedBox(height: 14),
                    if (e.description?.isNotEmpty == true) _aboutCard(e),
                    if (e.rawMaterials.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _guidelinesCard(e),
                    ],
                    const SizedBox(height: 14),
                    _reviewsCard(e),
                    const SizedBox(height: 14),
                    _hostCard(e),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero with back / share ─────────────────────────────────
  Widget _hero(EventDetail e) {
    final topPad = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        SizedBox(
          height: 230,
          width: double.infinity,
          child: e.photoUrl != null && e.photoUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: AppConfig.assetUrl(e.photoUrl!),
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: AppColors.primarySurface),
                  errorWidget: (_, _, _) => _heroFallback(),
                )
              : _heroFallback(),
        ),
        Positioned(
          top: topPad + 6,
          left: 12,
          right: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _circleBtn(Icons.arrow_back, () => Navigator.of(context).maybePop()),
              _circleBtn(Icons.share_outlined, () {}),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroFallback() => Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: const Center(child: Icon(Icons.celebration_rounded, color: Colors.white, size: 56)),
      );

  Widget _circleBtn(IconData icon, VoidCallback onTap) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 20, color: AppColors.ink)),
        ),
      );

  // ── Main info card ─────────────────────────────────────────
  Widget _infoCard(EventDetail e) {
    final dateLabel = e.date != null ? DateFormat('EEEE, MMMM d').format(e.date!) : '';
    final time = _timeRange(e);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(e.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19, color: AppColors.ink)),
              ),
              const SizedBox(width: 8),
              Row(children: [
                const Icon(Icons.star_rounded, color: AppColors.warning, size: 18),
                const SizedBox(width: 2),
                Text(
                  e.ratingAvg != null ? '${e.ratingAvg!.toStringAsFixed(1)}(${e.ratingCount})' : 'New',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink),
                ),
              ]),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  e.isPaid ? '₹${(e.price ?? 0).toStringAsFixed(0)}' : 'Free',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              const Spacer(),
              _joinButton(e),
            ],
          ),
          const SizedBox(height: 14),
          _metaRow(Icons.calendar_today_outlined, time.isNotEmpty ? '$dateLabel  |  $time' : dateLabel),
          if (e.location != null && e.location!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _metaRow(Icons.location_on_outlined, e.location!),
          ],
          const SizedBox(height: 8),
          _metaRow(Icons.person_outline, 'Hosted By : ${e.host.name}'),
        ],
      ),
    );
  }

  Widget _joinButton(EventDetail e) {
    if (_busy) {
      return const SizedBox(
        height: 40,
        width: 40,
        child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (e.needsPayment) {
      return _filledBtn('Pay ₹${(e.price ?? 0).toStringAsFixed(0)}', () => _pay(e));
    }
    if (e.isJoined) {
      return OutlinedButton.icon(
        onPressed: () => _withdraw(e),
        icon: const Icon(Icons.check_circle, size: 18, color: AppColors.primary),
        label: const Text('Joined'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(110, 40),
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
    return _filledBtn(e.isPaid ? 'Join ₹${(e.price ?? 0).toStringAsFixed(0)}' : 'Join', () => _join(e));
  }

  Widget _filledBtn(String label, VoidCallback onTap) => ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(120, 40),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  Widget _metaRow(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
        ],
      );

  // ── About / guidelines / reviews / host ────────────────────
  Widget _aboutCard(EventDetail e) => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('About the Workshop'),
            const SizedBox(height: 8),
            Text(e.description!, style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary)),
          ],
        ),
      );

  Widget _guidelinesCard(EventDetail e) => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('What to Bring / Guidelines'),
            const SizedBox(height: 10),
            ...e.rawMaterials.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    ),
                    Expanded(child: Text(m, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary))),
                  ]),
                )),
          ],
        ),
      );

  Widget _reviewsCard(EventDetail e) => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: _CardTitle('Verified Review')),
                if (e.reviews.length > 2)
                  const Text('View All >',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Verified Reviews from your area',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            if (e.reviews.isEmpty)
              const Text('No reviews yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted))
            else
              ...e.reviews.take(3).map((r) => _reviewTile(r)),
            const Divider(height: 24, color: AppColors.divider),
            const Text('Submit a Review', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (i) {
                final filled = i < _stars;
                return GestureDetector(
                  onTap: () => setState(() => _stars = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(filled ? Icons.star_rounded : Icons.star_border_rounded,
                        color: filled ? AppColors.warning : AppColors.textMuted, size: 28),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _review,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Share your experience....',
                filled: true,
                fillColor: AppColors.field,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.4)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Submit', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );

  Widget _reviewTile(EventReview r) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(name: r.raterName, radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(r.raterName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    ),
                    const SizedBox(width: 8),
                    Text(r.raterTypeLabel,
                        style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                  if (r.review?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(r.review!, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            RatingBadge(value: r.rating.toDouble()),
          ],
        ),
      );

  Widget _hostCard(EventDetail e) => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('About Host'),
            const SizedBox(height: 12),
            Row(
              children: [
                Avatar(name: e.host.name, photoUrl: e.host.photoUrl, radius: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.host.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      if (e.host.service != null)
                        Text(e.host.service!, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      if (e.host.location != null)
                        Row(children: [
                          const Icon(Icons.location_on, size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(e.host.location!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ),
                        ]),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _error() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 52, color: AppColors.textMuted),
              const SizedBox(height: 14),
              const Text("Couldn't load this event", style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              OutlinedButton(
                  onPressed: () => ref.invalidate(eventDetailProvider(widget.id)), child: const Text('Retry')),
            ],
          ),
        ),
      );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink));
}

/// `7:00 am - 8:00 am` from the event's start time + duration.
String _timeRange(EventDetail e) {
  if (e.startTime == null) return '';
  String fmt(DateTime d) => DateFormat('h:mm a').format(d).toLowerCase();
  final start = e.startTime!;
  if (e.durationMinutes != null && e.durationMinutes! > 0) {
    return '${fmt(start)} - ${fmt(start.add(Duration(minutes: e.durationMinutes!)))}';
  }
  return fmt(start);
}
