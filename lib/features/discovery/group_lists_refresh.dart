import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/data/home_repository.dart';
import 'discovery_repository.dart';

extension GroupListsRefresh on WidgetRef {
  /// Drops every cached list a group can appear in, so a create / edit / join / leave shows
  /// up everywhere at once: My Groups (Your Groups, Groups Joined, Groups near you), the Groups
  /// tab, Home (its Groups section, plus any area-scoped one), and profiles' Interest Groups.
  /// Screens not on display refetch when they're next shown.
  void invalidateGroupLists({int? groupId}) {
    invalidate(myGroupsProvider);
    invalidate(groupsProvider);
    invalidate(discoverGroupsProvider);
    invalidate(homeFeedProvider);
    invalidate(groupsSectionScopedProvider);
    invalidate(serviceProviderDetailProvider);
    invalidate(publicProfileProvider);
    if (groupId != null) invalidate(groupDetailProvider(groupId));
  }
}
