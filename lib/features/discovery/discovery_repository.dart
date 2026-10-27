import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../business/data/availability_models.dart';
import '../../core/auth/auth_scope.dart';
import '../home/data/home_models.dart';
import '../home/data/home_repository.dart';
import 'data/blocked_user_models.dart';
import 'data/event_detail_models.dart';
import 'data/group_detail_models.dart';
import 'data/my_activity_models.dart';
import 'data/public_profile_models.dart';
import 'data/service_catalog_models.dart';
import 'data/sp_detail_models.dart';

class DiscoveryRepository {
  DiscoveryRepository(this._dio);
  final Dio _dio;

  /// One page of a Discover list with the backend's real total, scoped like Home: [scope] is
  /// the member's society / lane / area / city, and [areaId] a picked area (with `area`).
  Future<Section<T>> _discoverPage<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    String scope = 'city',
    int? areaId,
  }) async {
    final res = await _dio.get(path, queryParameters: {
      'pageSize': 50,
      'scope': scope,
      'areaId': ?areaId,
    });
    return Section(
      total: ((res.data['meta'] as Map?)?['total'] as num?)?.toInt() ?? (res.data['data'] as List).length,
      items: (res.data['data'] as List).map((e) => fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<Section<ServiceProviderItem>> discoverServiceProviders({String scope = 'city', int? areaId}) =>
      _discoverPage('/service-providers', ServiceProviderItem.fromJson, scope: scope, areaId: areaId);
  Future<Section<WorkshopItem>> discoverEvents({String scope = 'city', int? areaId}) =>
      _discoverPage('/events', WorkshopItem.fromJson, scope: scope, areaId: areaId);
  Future<Section<GroupItem>> discoverGroups({String scope = 'city', int? areaId}) =>
      _discoverPage('/groups', GroupItem.fromJson, scope: scope, areaId: areaId);

  /// Every approved service by category, with how many providers in scope offer each: the
  /// All Services page behind Home's "Explore More" (BUG-087).
  Future<List<ServiceCatalogCategory>> serviceCatalog({String scope = 'city', int? areaId}) async {
    final res = await _dio.get('/service-providers/services', queryParameters: {'scope': scope, 'areaId': ?areaId});
    return ((res.data['data'] as List?) ?? [])
        .map((e) => ServiceCatalogCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The providers in scope offering one service: what an All Services tile opens.
  Future<Section<ServiceProviderItem>> providersForService(int subcategoryId, {String scope = 'city', int? areaId}) async {
    final res = await _dio.get('/service-providers', queryParameters: {
      'subcategoryId': subcategoryId,
      'pageSize': 50,
      'scope': scope,
      'areaId': ?areaId,
    });
    return Section(
      total: ((res.data['meta'] as Map?)?['total'] as num?)?.toInt() ?? (res.data['data'] as List).length,
      items: (res.data['data'] as List).map((e) => ServiceProviderItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<List<ServiceProviderItem>> serviceProviders({String? q}) async {
    final res = await _dio.get('/service-providers',
        queryParameters: {'pageSize': 50, if (q != null && q.isNotEmpty) 'q': q});
    return (res.data['data'] as List)
        .map((e) => ServiceProviderItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Service providers in the areas picked in Home's "Service provider in X ▾" header
  /// (distinct from the whole-feed [HomeScopeState] scoping).
  Future<Section<ServiceProviderItem>> serviceProvidersScoped(List<int> areaIds, {int pageSize = 8}) async {
    final res = await _dio.get('/service-providers',
        queryParameters: {'areaIds': areaIds.join(','), 'pageSize': pageSize});
    return Section(
      total: (res.data['meta']['total'] as num).toInt(),
      items: (res.data['data'] as List).map((e) => ServiceProviderItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<ServiceProviderDetail> serviceProvider(int id) async {
    final res = await _dio.get('/service-providers/$id');
    return ServiceProviderDetail.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Open, bookable time slots for an SP (from their published availability).
  Future<List<OpenSlot>> serviceProviderSlots(int id, {int days = 14}) async {
    final res = await _dio.get('/service-providers/$id/slots', queryParameters: {'days': days});
    return (res.data['data'] as List).map((e) => OpenSlot.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> submitReview(int id, {required int rating, String? review}) async {
    await _dio.post('/service-providers/$id/ratings', data: {
      'rating': rating,
      if (review != null && review.trim().isNotEmpty) 'review': review.trim(),
    });
  }

  /// Events to discover. [upcoming]: from today on, soonest first — My Events → Events near
  /// you, which used to fill up with the oldest past events.
  Future<List<WorkshopItem>> events({String? q, bool upcoming = false}) async {
    final res = await _dio.get('/events', queryParameters: {
      'pageSize': 50,
      if (q != null && q.isNotEmpty) 'q': q,
      if (upcoming) 'upcoming': 'true',
    });
    return (res.data['data'] as List)
        .map((e) => WorkshopItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Workshops/events in the areas picked in Home's "Workshops in X ▾" header.
  Future<Section<WorkshopItem>> eventsScoped(List<int> areaIds, {int pageSize = 6}) async {
    final res = await _dio.get('/events', queryParameters: {'areaIds': areaIds.join(','), 'pageSize': pageSize});
    return Section(
      total: (res.data['meta']['total'] as num).toInt(),
      items: (res.data['data'] as List).map((e) => WorkshopItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Groups in the member's city. [excludeMine] leaves out the ones they created, joined or
  /// are waiting to be approved for (My Groups → "Groups near you").
  Future<List<GroupItem>> groups({String? q, bool excludeMine = false}) async {
    final res = await _dio.get('/groups', queryParameters: {
      'pageSize': 50,
      if (q != null && q.isNotEmpty) 'q': q,
      if (excludeMine) 'excludeMine': 'true',
    });
    return (res.data['data'] as List)
        .map((e) => GroupItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Groups in the areas picked in Home's "Groups in X ▾" header.
  Future<Section<GroupItem>> groupsScoped(List<int> areaIds, {int pageSize = 6}) async {
    final res = await _dio.get('/groups', queryParameters: {'areaIds': areaIds.join(','), 'pageSize': pageSize});
    return Section(
      total: (res.data['meta']['total'] as num).toInt(),
      items: (res.data['data'] as List).map((e) => GroupItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  // ── Events lifecycle ───────────────────────────────────────
  Future<EventDetail> event(int id) async {
    final res = await _dio.get('/events/$id');
    return EventDetail.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> joinEvent(int id) async => _dio.post('/events/$id/join');
  Future<void> withdrawEvent(int id) async => _dio.post('/events/$id/withdraw');

  Future<void> payForEvent(int id, {String? couponCode}) async {
    await _dio.post('/events/$id/pay', data: {if (couponCode != null && couponCode.isNotEmpty) 'couponCode': couponCode});
  }

  Future<void> rateEvent(int id, {required int rating, String? review}) async {
    await _dio.post('/events/$id/ratings', data: {
      'rating': rating,
      if (review != null && review.trim().isNotEmpty) 'review': review.trim(),
    });
  }

  /// Creates an event and returns its new id.
  Future<int> createEvent(Map<String, dynamic> data) async {
    final res = await _dio.post('/events', data: data);
    return (res.data['data']['id'] as num).toInt();
  }

  Future<void> updateEvent(int id, Map<String, dynamic> data) async => _dio.patch('/events/$id', data: data);

  /// Events the current user hosts vs. has joined.
  Future<MyEvents> myEvents() async {
    final res = await _dio.get('/events/mine');
    return MyEvents.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Uploads an image to the shared media endpoint and returns its URL.
  Future<String> uploadImage(String filePath, {String? type}) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      if (type != null) 'type': type,
    });
    final res = await _dio.post('/media', data: form);
    return res.data['data']['url'] as String;
  }

  // ── Groups lifecycle ───────────────────────────────────────
  Future<GroupDetail> group(int id) async {
    final res = await _dio.get('/groups/$id');
    return GroupDetail.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Joins a free group. Returns the membership status: `joined`, or `pending_approval` when
  /// the admin vets members. A paid group answers 402 (join by paying instead).
  Future<String?> joinGroup(int id) async {
    final res = await _dio.post('/groups/$id/join');
    final data = res.data is Map ? res.data['data'] : null;
    return data is Map ? data['status'] as String? : null;
  }

  /// Group discussions, optionally narrowed to one area — backs the header dropdown.
  Future<List<DiscussionItem>> groupDiscussions(int id, {int? areaId}) async {
    final res = await _dio.get('/groups/$id/discussions',
        queryParameters: {if (areaId != null) 'areaId': areaId});
    return ((res.data['data'] as List?) ?? [])
        .map((e) => DiscussionItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GroupMember>> groupMembers(int id) async {
    final res = await _dio.get('/groups/$id/members');
    return ((res.data['data'] as List?) ?? [])
        .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setGroupMuted(int id, bool muted) async =>
      _dio.post('/groups/$id/mute', data: {'muted': muted});

  /// Hides the group's existing discussions from this member only.
  Future<void> clearGroupChat(int id) async => _dio.post('/groups/$id/clear-chat');
  /// Leaves a group. The admin names the member taking over ([newAdminUserId]); as the only
  /// member, they leave it out and the group closes (BUG-081).
  Future<void> leaveGroup(int id, {int? newAdminUserId}) async =>
      _dio.post('/groups/$id/leave', data: {'newAdminUserId': ?newAdminUserId});

  Future<void> payForGroup(int id, {String? couponCode}) async {
    await _dio.post('/groups/$id/pay', data: {if (couponCode != null && couponCode.isNotEmpty) 'couponCode': couponCode});
  }

  Future<void> rateGroup(int id, {required int rating, String? review}) async {
    await _dio.post('/groups/$id/ratings', data: {
      'rating': rating,
      if (review != null && review.trim().isNotEmpty) 'review': review.trim(),
    });
  }

  Future<void> postToGroup(int id, {required String text}) async {
    await _dio.post('/groups/$id/posts', data: {'textContent': text});
  }

  /// Creates a group and returns its new id.
  Future<int> createGroup(Map<String, dynamic> data) async {
    final res = await _dio.post('/groups', data: data);
    return (res.data['data']['id'] as num).toInt();
  }

  Future<void> updateGroup(int id, Map<String, dynamic> data) async => _dio.patch('/groups/$id', data: data);

  /// Groups the current user owns vs. has joined.
  Future<MyGroups> myGroups() async {
    final res = await _dio.get('/groups/mine');
    return MyGroups.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Every review the current user has submitted, across SPs/events/groups.
  Future<MyReviews> myReviews() async {
    final res = await _dio.get('/reviews/mine');
    return MyReviews.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Public profile of any member (resident or SP), keyed by profile id.
  Future<PublicProfile> publicProfile(int id) async {
    final res = await _dio.get('/profiles/$id');
    return PublicProfile.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Reports a profile (by profile id) for abuse.
  Future<void> reportProfile(int profileId, {required String reason}) async {
    await _dio.post('/profiles/$profileId/report', data: {'reason': reason});
  }

  /// Logs a profile share (by profile id).
  Future<void> shareProfile(int profileId) async {
    await _dio.post('/profiles/$profileId/share', data: {'channel': 'in_app'});
  }

  /// Blocks/unblocks a member by their *user* id (not profile id).
  Future<void> blockUser(int userId, {String? reason}) async {
    await _dio.post('/users/$userId/block', data: {'reason': ?reason});
  }

  Future<void> unblockUser(int userId) async => _dio.delete('/users/$userId/block');

  Future<bool> blockStatus(int userId) async {
    final res = await _dio.get('/users/$userId/block-status');
    return (res.data['data'] as Map<String, dynamic>)['blocked'] as bool? ?? false;
  }

  Future<List<BlockedUserItem>> listBlockedUsers() async {
    final res = await _dio.get('/users/blocked');
    return (res.data['data'] as List).map((e) => BlockedUserItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>((ref) {
  return DiscoveryRepository(ref.watch(dioProvider));
});

// The Services, Events and Groups tabs follow the app-wide location ([homeScopeProvider]) —
// the same one Home's top selector sets — so a location picked anywhere applies everywhere.
final discoverServiceProvidersProvider = FutureProvider<Section<ServiceProviderItem>>((ref) {
  ref.bindToAccount();
  final s = ref.watch(homeScopeProvider);
  return ref.watch(discoveryRepositoryProvider).discoverServiceProviders(scope: s.scope, areaId: s.overrideAreaId);
});
/// All Services (BUG-087), for the app-wide location.
final serviceCatalogProvider = FutureProvider<List<ServiceCatalogCategory>>((ref) {
  ref.bindToAccount();
  final s = ref.watch(homeScopeProvider);
  return ref.watch(discoveryRepositoryProvider).serviceCatalog(scope: s.scope, areaId: s.overrideAreaId);
});

/// The providers of one service (by subcategory id), for the app-wide location.
final providersForServiceProvider = FutureProvider.family<Section<ServiceProviderItem>, int>((ref, subcategoryId) {
  ref.bindToAccount();
  final s = ref.watch(homeScopeProvider);
  return ref
      .watch(discoveryRepositoryProvider)
      .providersForService(subcategoryId, scope: s.scope, areaId: s.overrideAreaId);
});

final discoverEventsProvider = FutureProvider<Section<WorkshopItem>>((ref) {
  ref.bindToAccount();
  final s = ref.watch(homeScopeProvider);
  return ref.watch(discoveryRepositoryProvider).discoverEvents(scope: s.scope, areaId: s.overrideAreaId);
});
final discoverGroupsProvider = FutureProvider<Section<GroupItem>>((ref) {
  ref.bindToAccount();
  final s = ref.watch(homeScopeProvider);
  return ref.watch(discoveryRepositoryProvider).discoverGroups(scope: s.scope, areaId: s.overrideAreaId);
});

final serviceProvidersProvider = FutureProvider<List<ServiceProviderItem>>((ref) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).serviceProviders();
});

/// My Events → "Events near you": today onwards, soonest first.
final eventsProvider = FutureProvider<List<WorkshopItem>>((ref) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).events(upcoming: true);
});

/// My Groups → "Groups near you": groups to discover, without the member's own or joined ones.
final groupsProvider = FutureProvider<List<GroupItem>>((ref) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).groups(excludeMine: true);
});

/// Full service-provider profile, keyed by profile id.
final serviceProviderDetailProvider = FutureProvider.family<ServiceProviderDetail, int>((ref, id) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).serviceProvider(id);
});

/// Open bookable slots for an SP, keyed by profile id.
final spSlotsProvider = FutureProvider.family<List<OpenSlot>, int>((ref, id) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).serviceProviderSlots(id);
});

/// Service providers/events/groups for a Home section's picked areas, keyed by
/// [SectionAreas.key] ("3,7") — backs the per-section area dropdowns (see
/// `home/data/home_repository.dart`).
final spSectionScopedProvider = FutureProvider.family<Section<ServiceProviderItem>, String>((ref, areaKey) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).serviceProvidersScoped(areaIdsOf(areaKey));
});
final workshopsSectionScopedProvider = FutureProvider.family<Section<WorkshopItem>, String>((ref, areaKey) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).eventsScoped(areaIdsOf(areaKey));
});
final groupsSectionScopedProvider = FutureProvider.family<Section<GroupItem>, String>((ref, areaKey) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).groupsScoped(areaIdsOf(areaKey));
});

/// Full event detail, keyed by event id.
final eventDetailProvider = FutureProvider.family<EventDetail, int>((ref, id) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).event(id);
});

/// Full group detail, keyed by group id.
final groupDetailProvider = FutureProvider.family<GroupDetail, int>((ref, id) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).group(id);
});

/// Group discussions narrowed to one area, keyed by (groupId, areaId) — backs the group
/// profile's own header dropdown, the same way Home scopes its sections.
class GroupAreaKey {
  const GroupAreaKey(this.groupId, this.areaId);
  final int groupId;
  final int areaId;
  @override
  bool operator ==(Object other) =>
      other is GroupAreaKey && other.groupId == groupId && other.areaId == areaId;
  @override
  int get hashCode => Object.hash(groupId, areaId);
}

final groupDiscussionsScopedProvider =
    FutureProvider.family<List<DiscussionItem>, GroupAreaKey>((ref, key) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).groupDiscussions(key.groupId, areaId: key.areaId);
});

/// A member's public profile, keyed by profile id.
final publicProfileProvider = FutureProvider.family<PublicProfile, int>((ref, id) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).publicProfile(id);
});

/// The current user's own hosted/joined events, owned/joined groups, and submitted reviews —
/// back the Profile tab's "Events" / "Groups" / "Reviews" screens.
final myEventsProvider = FutureProvider<MyEvents>((ref) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).myEvents();
});
final myGroupsProvider = FutureProvider<MyGroups>((ref) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).myGroups();
});
final myReviewsProvider = FutureProvider<MyReviews>((ref) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).myReviews();
});

/// Shared search query for the Discover screen — lists are filtered client-side
/// so tab counts and results update live as the user types.
class DiscoverQuery extends Notifier<String> {
  @override
  String build() {
    ref.bindToAccount();
    return '';
  }
  void set(String value) => state = value;
}

final discoverQueryProvider = NotifierProvider<DiscoverQuery, String>(DiscoverQuery.new);

/// Active Discover tab: 0 = All, 1 = Events, 2 = Service Providers, 3 = Groups.
/// Shared so the bottom nav (Services/Events/Groups) and the in-screen tab row
/// stay in sync.
class DiscoverTab extends Notifier<int> {
  @override
  int build() {
    ref.bindToAccount();
    return 0;
  }
  void set(int value) => state = value;
}

final discoverTabProvider = NotifierProvider<DiscoverTab, int>(DiscoverTab.new);
