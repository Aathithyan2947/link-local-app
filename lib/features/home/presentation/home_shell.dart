import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'home_feed_screen.dart';
import 'tabs/events_tab.dart';
import 'tabs/explore_tab.dart';
import 'tabs/profile_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    HomeFeedScreen(),
    ExploreTab(),
    EventsTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySurface,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: AppColors.primary), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search, color: AppColors.primary), label: 'Explore'),
          NavigationDestination(
              icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event, color: AppColors.primary), label: 'Events'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: AppColors.primary), label: 'Profile'),
        ],
      ),
    );
  }
}
