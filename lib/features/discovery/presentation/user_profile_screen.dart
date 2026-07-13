import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/data/home_models.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../../messages/presentation/chat_screen.dart';
import '../data/public_profile_models.dart';
import '../data/sp_detail_models.dart';
import '../discovery_repository.dart';
import 'event_detail_screen.dart';
import 'group_profile_screen.dart';
import 'widgets/discover_cards.dart';

/// A member's public profile — the "User" frame. About / Education / Profession
/// / Events / Posts / Interest Groups, with a Message CTA.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(publicProfileProvider(id));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: OutlinedButton(
              onPressed: () => ref.invalidate(publicProfileProvider(id)), child: const Text('Retry')),
        ),
        data: (p) => RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(publicProfileProvider(id)),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _header(context, p),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.aboutMe?.isNotEmpty == true) _card(_about('About Me', p.aboutMe!)),
                    if (p.educations.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _card(_list('Education', p.educations.map((e) => e.institution != null ? '${e.label} · ${e.institution}' : e.label).toList())),
                    ],
                    if (p.professions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _card(_list('Profession', p.professions.map((e) => e.label).toList())),
                    ],
                    if (p.servicesContacted > 0) ...[
                      const SizedBox(height: 12),
                      _card(Row(
                        children: [
                          const Icon(Icons.handshake_outlined, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('${p.servicesContacted} Service Providers contacted',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          ),
                        ],
                      )),
                    ],
                  ],
                ),
              ),
              if (p.events.isNotEmpty) _events(context, p.events),
              if (p.posts.isNotEmpty) _posts(p.posts),
              if (p.groups.isNotEmpty) _groups(context, p.groups),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────
  Widget _header(BuildContext context, PublicProfile p) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, topPad + 8, 16, 20),
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
                onTap: () => Navigator.of(context).maybePop(),
                behavior: HitTestBehavior.opaque,
                child: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Blocking coming soon'))),
                child: const Text('Block', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              CircleAvatar(radius: 36, backgroundColor: Colors.white, child: Avatar(name: p.name, photoUrl: p.photoUrl, radius: 34)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
                    if (p.locationLabel != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.location_on, size: 14, color: Colors.white70),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(p.locationLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChatScreen(otherUserId: p.userId, otherName: p.name, otherPhoto: p.photoUrl),
              )),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Message'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                elevation: 0,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sections ───────────────────────────────────────────────
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

  Widget _about(String title, String body) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary)),
        ],
      );

  Widget _list(String title, List<String> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink)),
          const SizedBox(height: 6),
          ...items.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(s, style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
              )),
        ],
      );

  Widget _events(BuildContext context, List<SpEvent> events) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 0, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(right: 20, bottom: 12),
              child: Text('Event(s)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
            ),
            SizedBox(
              height: 196,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: events.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _eventCard(context, events[i]),
              ),
            ),
          ],
        ),
      );

  Widget _eventCard(BuildContext context, SpEvent item) {
    final e = item.event;
    final date = e.date != null ? DateFormat('EEE, MMM d').format(e.date!) : '';
    final closed = item.isPast;
    final label = closed ? 'Closed' : (item.isHosting ? 'Hosting' : 'Attending');
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(id: e.id))),
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(children: [
              NetworkThumb(
                photoUrl: e.photoUrl,
                fallbackIcon: Icons.celebration_rounded,
                width: double.infinity,
                height: 88,
                radius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: closed ? AppColors.textMuted : AppColors.primary, borderRadius: BorderRadius.circular(6)),
                  child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 4),
                  Text(date, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  if (e.location != null && e.location!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(e.location!,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posts(List<DiscussionItem> posts) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Posts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
            const SizedBox(height: 12),
            ...posts.take(3).map((d) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Avatar(name: d.authorName, photoUrl: d.authorPhoto, radius: 16),
                        const SizedBox(width: 10),
                        Text(d.authorName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ]),
                      if (d.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(d.text, style: const TextStyle(fontSize: 14)),
                      ],
                    ],
                  ),
                )),
          ],
        ),
      );

  Widget _groups(BuildContext context, List<SpGroup> groups) {
    final admin = groups.where((g) => g.role == 'admin').toList();
    final member = groups.where((g) => g.role == 'member').toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Interest Groups', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (admin.isNotEmpty) Expanded(child: _groupCol(context, 'Admin', admin)),
              if (member.isNotEmpty) Expanded(child: _groupCol(context, 'Member', member)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupCol(BuildContext context, String label, List<SpGroup> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: items
                .map((g) => GestureDetector(
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => GroupProfileScreen(id: g.group.id))),
                      child: SizedBox(
                        width: 80,
                        child: Column(
                          children: [
                            NetworkThumb(
                              photoUrl: g.group.photoUrl,
                              fallbackIcon: Icons.groups_rounded,
                              width: 60,
                              height: 60,
                              radius: BorderRadius.circular(30),
                            ),
                            const SizedBox(height: 6),
                            Text(g.group.title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      );
}
