import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/data/home_repository.dart';
import 'discovery_repository.dart';

extension EventListsRefresh on WidgetRef {
  /// Drops every cached list an event can appear in, so a create/edit/join/withdraw shows
  /// up everywhere at once: Home (its Workshops section and Events count, plus any
  /// area-scoped Workshops), the Events tab, My Events, and provider profiles' Event(s).
  /// Screens not on display refetch when they're next shown.
  void invalidateEventLists() {
    invalidate(homeFeedProvider);
    invalidate(workshopsSectionScopedProvider);
    invalidate(eventsProvider);
    invalidate(discoverEventsProvider);
    invalidate(myEventsProvider);
    invalidate(serviceProviderDetailProvider);
  }
}
