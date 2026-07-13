import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../discovery/discovery_repository.dart';
import '../../discovery/presentation/create_event_screen.dart';
import '../../discovery/presentation/create_group_screen.dart';
import '../../discovery/presentation/discover_screen.dart';
import '../../feed/presentation/create_post_screen.dart';
import 'home_feed_screen.dart';
import 'tabs/profile_tab.dart';

/// App shell: Home feed + the unified Discover surface, under a custom bottom
/// bar (Home · Services · ➕ · Events · Groups) with a raised center FAB.
/// Services / Events / Groups all open Discover, pre-selecting the matching tab.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  // 0 = Home feed, 1 = Discover.
  int _body = 0;

  void _goHome() => setState(() => _body = 0);

  void _openDiscover(int discoverTab) {
    ref.read(discoverTabProvider.notifier).set(discoverTab);
    setState(() => _body = 1);
  }

  void _openProfile() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileTab()));
  }

  /// Which bottom-nav slot is highlighted (0 Home · 1 Services · 3 Events · 4 Groups).
  int _activeSlot(int discoverTab) {
    if (_body == 0) return 0;
    return switch (discoverTab) {
      2 => 1, // Service Providers → Services
      3 => 4, // Groups
      _ => 3, // Events (also the default for the "All" tab)
    };
  }

  @override
  Widget build(BuildContext context) {
    final discoverTab = ref.watch(discoverTabProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: IndexedStack(
        index: _body,
        children: [
          HomeFeedScreen(onProfile: _openProfile),
          DiscoverScreen(onBack: _goHome),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        activeSlot: _activeSlot(discoverTab),
        onHome: _goHome,
        onServices: () => _openDiscover(2),
        onEvents: () => _openDiscover(1),
        onGroups: () => _openDiscover(3),
        onCreate: _showCreateSheet,
      ),
    );
  }

  void _showCreateSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            _createTile(ctx, Icons.post_add_rounded, 'Create a Post', 'Ask, offer help or share an update',
                onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                    )),
            _createTile(ctx, Icons.event_rounded, 'Host an Event', 'Organise a workshop or meetup',
                onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreateEventScreen()),
                    )),
            _createTile(ctx, Icons.groups_rounded, 'Start a Group', 'Bring neighbours together',
                onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                    )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _createTile(BuildContext ctx, IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primarySurface,
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5)),
      onTap: () {
        Navigator.of(ctx).pop();
        if (onTap != null) {
          onTap();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('“$title” is coming soon')),
          );
        }
      },
    );
  }
}

// ── Custom bottom bar with center FAB ────────────────────────
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.activeSlot,
    required this.onHome,
    required this.onServices,
    required this.onEvents,
    required this.onGroups,
    required this.onCreate,
  });
  final int activeSlot;
  final VoidCallback onHome;
  final VoidCallback onServices;
  final VoidCallback onEvents;
  final VoidCallback onGroups;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: 66 + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The bar
          Container(
            height: 66 + bottomInset,
            padding: EdgeInsets.only(bottom: bottomInset),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: [
                BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4)),
              ],
            ),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                  active: activeSlot == 0,
                  onTap: onHome,
                ),
                _NavItem(
                  icon: Icons.handyman_outlined,
                  activeIcon: Icons.handyman_rounded,
                  label: 'Services',
                  active: activeSlot == 1,
                  onTap: onServices,
                ),
                const SizedBox(width: 64), // gap for the FAB
                _NavItem(
                  icon: Icons.storefront_outlined,
                  activeIcon: Icons.storefront_rounded,
                  label: 'Events',
                  active: activeSlot == 3,
                  onTap: onEvents,
                ),
                _NavItem(
                  icon: Icons.groups_outlined,
                  activeIcon: Icons.groups_rounded,
                  label: 'Groups',
                  active: activeSlot == 4,
                  onTap: onGroups,
                ),
              ],
            ),
          ),
          // Raised center FAB
          Positioned(
            top: -22,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: onCreate,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 4),
                    boxShadow: const [
                      BoxShadow(color: Color(0x330E9F6E), blurRadius: 12, offset: Offset(0, 4)),
                    ],
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? activeIcon : icon, color: color, size: 26),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
