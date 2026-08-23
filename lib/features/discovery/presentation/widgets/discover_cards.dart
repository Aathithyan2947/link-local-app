import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../home/data/home_models.dart';
import '../../../home/presentation/widgets/home_widgets.dart';

// ── Small shared pieces ──────────────────────────────────────

/// Green rating pill (e.g. `4.3`). Shows `New` when there are no ratings yet.
class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, this.value, this.compact = false});
  final double? value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = value != null ? value!.toStringAsFixed(1) : 'New';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 8, vertical: compact ? 1 : 3),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 10 : 12,
        ),
      ),
    );
  }
}

/// Compact filled "Join" pill used on event cards.
class JoinButton extends StatelessWidget {
  const JoinButton({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Text('Join',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
        ),
      ),
    );
  }
}

/// Non-interactive "Joined" badge — same visual weight as [JoinButton], but a
/// status marker rather than an action, for items the user already belongs to.
class JoinedBadge extends StatelessWidget {
  const JoinedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary),
      ),
      child: const Text('Joined',
          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Rounded network image with a branded gradient fallback + icon.
class NetworkThumb extends StatelessWidget {
  const NetworkThumb({
    super.key,
    required this.photoUrl,
    required this.fallbackIcon,
    required this.width,
    required this.height,
    required this.radius,
  });
  final String? photoUrl;
  final IconData fallbackIcon;
  final double width;
  final double height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: radius),
          child: Icon(fallbackIcon, color: Colors.white, size: height * 0.4),
        );
    if (photoUrl == null || photoUrl!.isEmpty) return fallback();
    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: AppConfig.assetUrl(photoUrl!),
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(width: width, height: height, color: AppColors.primarySurface),
        errorWidget: (_, _, _) => fallback(),
      ),
    );
  }
}

/// `7:00 am - 8:00 am` (or just the start when there's no duration).
String eventTimeRange(WorkshopItem e) {
  if (e.startTime == null) return '';
  String fmt(DateTime d) => DateFormat('h:mm a').format(d).toLowerCase();
  final start = e.startTime!;
  if (e.durationMinutes != null && e.durationMinutes! > 0) {
    final end = start.add(Duration(minutes: e.durationMinutes!));
    return '${fmt(start)} - ${fmt(end)}';
  }
  return fmt(start);
}

// ── Event card ───────────────────────────────────────────────
/// Horizontal event card: [thumbnail | title · date|time · location · By ] with
/// a rating pill (top-right) and a Join button (bottom-right).
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.onTap, this.onJoin, this.trailing});
  final WorkshopItem event;
  final VoidCallback? onTap;
  final VoidCallback? onJoin;

  /// Overrides the bottom-right action (defaults to a Join button) — e.g. an Edit
  /// button or a status chip on the Profile tab's "My Events" screen.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dateLabel = event.date != null ? DateFormat('EEE, MMM d').format(event.date!) : '';
    final timeLabel = eventTimeRange(event);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: SizedBox(
            height: 108,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NetworkThumb(
                  photoUrl: event.photoUrl,
                  fallbackIcon: Icons.celebration_rounded,
                  width: 118,
                  height: 108,
                  radius: const BorderRadius.horizontal(left: Radius.circular(14)),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(event.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
                            ),
                            const SizedBox(width: 6),
                            RatingBadge(value: event.ratingAvg, compact: true),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            if (dateLabel.isNotEmpty)
                              Text(dateLabel,
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            if (dateLabel.isNotEmpty && timeLabel.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                height: 10,
                                width: 1,
                                color: AppColors.divider,
                              ),
                            if (timeLabel.isNotEmpty)
                              Text(timeLabel,
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          ],
                        ),
                        if (event.location != null && event.location!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 11, color: AppColors.textMuted),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(event.location!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 5),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(
                                'By : ${event.creatorName ?? 'Organizer'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                              ),
                            ),
                            const SizedBox(width: 8),
                            trailing ?? JoinButton(onTap: onJoin),
                          ],
                        ),
                      ],
                    ),
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

// ── Service provider card ────────────────────────────────────
/// [avatar | name · service · city|distance] with a rating pill top-right.
class SpCard extends StatelessWidget {
  const SpCard({super.key, required this.sp, required this.city, this.distance, this.onTap});
  final ServiceProviderItem sp;
  final String city;
  final String? distance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Avatar(name: sp.name, photoUrl: sp.photoUrl, radius: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sp.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
                      const SizedBox(height: 4),
                      Text(sp.service ?? 'Service Provider',
                          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(city,
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          if (distance != null) ...[
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              height: 13,
                              width: 1,
                              color: AppColors.divider,
                            ),
                            Text(distance!,
                                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: RatingBadge(value: sp.ratingAvg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Group card ───────────────────────────────────────────────
/// [image | title · N Members · Owner: name].
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.group, this.onTap, this.trailing});
  final GroupItem group;
  final VoidCallback? onTap;

  /// Optional trailing action — e.g. an Edit button or a Join button on the Profile
  /// tab's "My Groups" screen. Absent by default, matching the Discover tab's plain card.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                NetworkThumb(
                  photoUrl: group.photoUrl,
                  fallbackIcon: Icons.groups_rounded,
                  width: 64,
                  height: 64,
                  radius: BorderRadius.circular(32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
                      const SizedBox(height: 4),
                      Text('${group.members} Members',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                      if (group.ownerName != null) ...[
                        const SizedBox(height: 2),
                        Text('Owner: ${group.ownerName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
