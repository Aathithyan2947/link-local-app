import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/brand_wordmark.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/presentation/blackout_dates_screen.dart';
import '../../../business/presentation/setup/sp_setup_wizard_screen.dart';
import '../../../business/presentation/sp_dashboard_screen.dart';
import '../../../feed/presentation/feed_screen.dart';
import '../../../messages/presentation/conversations_screen.dart';
import '../../../discovery/presentation/my_events_screen.dart';
import '../../../discovery/presentation/my_groups_screen.dart';
import '../../../discovery/presentation/my_reviews_screen.dart';
import '../../../discovery/presentation/service_provider_detail_screen.dart';
import '../../../orders/presentation/orders_hub_screen.dart';
import '../../../orders/presentation/payments_screen.dart';
import '../../../profile/data/profile_models.dart';
import '../../../profile/data/profile_repository.dart';
import '../../../profile/presentation/blocked_users_screen.dart';
import '../../../profile/presentation/contact_visibility_screen.dart';
import '../../../profile/presentation/login_security_screen.dart';
import '../../../profile/presentation/notification_settings_screen.dart';
import '../../../profile/presentation/profile_visibility_screen.dart';
import '../../../profile/presentation/sections/basic_sections.dart';
import '../../../referrals/presentation/referrals_screen.dart';
import '../widgets/home_widgets.dart';

/// SP → their service subcategory (e.g. "Home Baker"); resident → their
/// profession if set; otherwise omitted, same as the other optional card lines.
String? _roleLabel(ProfileDetail? profile) {
  if (profile == null) return null;
  if (profile.isServiceProvider && profile.serviceTypes.isNotEmpty) return profile.serviceTypes.first.label;
  if (profile.professions.isNotEmpty) return profile.professions.first.label;
  return null;
}

/// The member's own profile — same destination for the card's Edit button and the "My
/// Profile" menu item below it, so both do the same job. `ServiceProviderDetailScreen`
/// itself trims down to the resident-appropriate sections when the owner isn't an SP.
void _openMyProfile(BuildContext context, WidgetRef ref) {
  final myId = ref.read(myProfileProvider).asData?.value.id;
  if (myId == null) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ServiceProviderDetailScreen(id: myId)));
}

/// The user's own profile — a settings hub (Profile Page frame): identity card
/// + Edit, then Personal / Transaction / Privacy menu sections, and Log Out.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  void _soon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('“$label” is coming soon')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final profile = ref.watch(myProfileProvider).value;
    final features = ref.watch(myProviderFeaturesProvider).asData?.value;
    final hasMenu = features?.hasMenu ?? false;
    final hasDateBooking = features?.hasDateBooking ?? false;
    final availability = ref.watch(myAvailabilityProvider).asData?.value.availability;
    final shopSettingsItems = user?.isServiceProvider != true
        ? const <_MenuItem>[]
        : [
            if (hasDateBooking)
              _MenuItem(Icons.event_available_outlined, 'Availability & schedule', () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SpSetupWizardScreen(
                    initialAvailability: availability,
                    initialName: user?.name,
                    hasMenu: hasMenu,
                    hasDateBooking: hasDateBooking,
                  ),
                ));
                ref.invalidate(myAvailabilityProvider);
              }),
            if (hasDateBooking)
              _MenuItem(Icons.event_busy_outlined, 'Off days',
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlackoutDatesScreen()))),
          ];
    return Scaffold(
      backgroundColor: AppColors.primarySurface,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _ProfileCard(
            name: user?.name ?? 'Member',
            role: _roleLabel(profile),
            address: profile?.address ?? user?.city,
            email: user?.email,
            phone: user?.mobile,
            photoUrl: user?.photoUrl,
            onEdit: () {
              if (user?.isServiceProvider == true) {
                _openMyProfile(context, ref);
              } else {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BasicInfoScreen()));
              }
            },
          ),
          // One card holding both, per the design. My Shop used to carry a mint fill of its own,
          // which read as a highlighted state it never actually had.
          _PlainSection([
            if (user?.isServiceProvider == true)
              _MenuItem(Icons.storefront_outlined, 'My Shop',
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpDashboardScreen()))),
            _MenuItem(Icons.account_circle_outlined, 'My Profile', () => _openMyProfile(context, ref)),
          ]),
          if (shopSettingsItems.isNotEmpty) _Section('My Shop Settings', shopSettingsItems),
          _Section('Personal', [
            _MenuItem(Icons.event_outlined, 'My Events',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyEventsScreen()))),
            _MenuItem(Icons.groups_outlined, 'My Groups',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyGroupsScreen()))),
            _MenuItem(Icons.star_border_rounded, 'My Reviews',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyReviewsScreen()))),
            _MenuItem(Icons.chat_bubble_outline, 'My Posts',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedScreen()))),
            _MenuItem(Icons.attach_money_rounded, 'My Referrals',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReferralsScreen()))),
          ]),
          _Section('Transaction History', [
            _MenuItem(Icons.credit_card_outlined, 'Payments',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaymentsScreen()))),
            _MenuItem(Icons.receipt_long_outlined, 'Order History',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersHubScreen()))),
            _MenuItem(Icons.forum_outlined, 'Messages',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConversationsScreen()))),
          ]),
          _Section('Privacy', [
            _MenuItem(Icons.visibility_outlined, 'Profile visibility',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileVisibilityScreen()))),
            _MenuItem(Icons.lock_outline, 'Log In & Change Password',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginSecurityScreen()))),
            _MenuItem(Icons.notifications_none_rounded, 'Notifications & Alerts',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()))),
            _MenuItem(Icons.block_outlined, 'Blocked users',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlockedUsersScreen()))),
            _MenuItem(Icons.contact_phone_outlined, 'Contact Details Visiblity',
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactVisibilityScreen()))),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _soon(context, 'Customer Care'),
                  icon: const Icon(Icons.headset_mic_outlined, color: AppColors.primary),
                  label: const Text('Customer Care'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                  icon: const Icon(Icons.logout, color: AppColors.error),
                  label: const Text('Log Out', style: TextStyle(color: AppColors.error)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    this.role,
    this.address,
    this.email,
    this.phone,
    this.photoUrl,
    required this.onEdit,
  });
  final String name;
  final String? role;
  final String? address;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Branding sits above the card, as in the design. The back control moves out of the
        // card with it — this screen is pushed, so it still needs one.
        Padding(
          padding: EdgeInsets.fromLTRB(10, topPad + 8, 16, 6),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.chevron_left, color: AppColors.ink, size: 28),
                ),
              ),
              const SizedBox(width: 2),
              const BrandWordmark(),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white,
                    child: Avatar(name: name, photoUrl: photoUrl, radius: 32),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20, height: 1.2)),
                        if (role != null && role!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(role!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                        ],
                        if (address != null && address!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(address!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                        if (email != null) _iconLine(Icons.mail_outline_rounded, email!),
                        if (phone != null) _iconLine(Icons.call_outlined, phone!),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Bottom-right of the card, per the design — it used to sit inside the text
              // column, where it read as another detail line rather than an action.
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_square, size: 16, color: Colors.white),
                  label: const Text('Edit',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                    minimumSize: const Size(0, 38),
                    side: const BorderSide(color: Colors.white),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _iconLine(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(
          children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 7),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ],
        ),
      );
}

/// The same white card as [_Section] but with no heading — used for the My Shop / My Profile
/// pair, which the design shows above the first titled group.
class _PlainSection extends StatelessWidget {
  const _PlainSection(this.items);
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++)
              _MenuItem(items[i].icon, items[i].label, items[i].onTap, last: i == items.length - 1),
          ],
        ),
      ),
    );
  }
}

/// A titled group of rows on its own white card. The page behind it is tinted, so the card
/// is what separates one group of settings from the next.
class _Section extends StatelessWidget {
  const _Section(this.title, this.items);
  final String title;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            // The trailing rule under the last row would otherwise float just above the card's
            // own bottom edge.
            for (var i = 0; i < items.length; i++)
              _MenuItem(items[i].icon, items[i].label, items[i].onTap, last: i == items.length - 1),
          ],
        ),
      ),
    );
  }
}

/// A single settings row. Also used as a plain data holder by [_Section], which rebuilds each
/// one to mark the last.
class _MenuItem extends StatelessWidget {
  const _MenuItem(this.icon, this.label, this.onTap, {this.last = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 22),
          ],
        ),
      ),
    );
  }
}
