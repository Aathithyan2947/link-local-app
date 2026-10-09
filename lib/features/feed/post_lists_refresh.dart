import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../discovery/discovery_repository.dart';
import '../home/data/home_repository.dart';
import 'data/feed_repository.dart';

extension PostListsRefresh on WidgetRef {
  /// Drops every cached list a new post can appear in, so it shows up everywhere at once:
  /// Home (its discussions, plus any area-scoped ones), Posts, and the author's own profile
  /// (provider or member) with its full list of posts. Screens not on display refetch when they're next shown.
  void invalidatePostLists() {
    invalidate(feedProvider);
    invalidate(userPostsProvider);
    invalidate(homeFeedProvider);
    invalidate(discussionsSectionScopedProvider);
    invalidate(serviceProviderDetailProvider);
    invalidate(publicProfileProvider);
  }
}
