import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../business/data/availability_models.dart';
import '../../core/auth/auth_scope.dart';
import '../home/data/home_models.dart';
import 'data/event_detail_models.dart';
import 'data/group_detail_models.dart';
import 'data/public_profile_models.dart';
import 'data/sp_detail_models.dart';

class DiscoveryRepository {
  DiscoveryRepository(this._dio);
  final Dio _dio;

  Future<List<ServiceProviderItem>> serviceProviders({String? q}) async {
    final res = await _dio.get('/service-providers',
        queryParameters: {'pageSize': 50, if (q != null && q.isNotEmpty) 'q': q});
    return (res.data['data'] as List)
        .map((e) => ServiceProviderItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Service providers narrowed to a single picked area — powers the Home feed's
  /// "Service provider in X ▾" section header when a per-section area is chosen (distinct
  /// from the whole-feed [HomeScopeState] scoping).
  Future<Section<ServiceProviderItem>> serviceProvidersScoped(int areaId, {int pageSize = 8}) async {
    final res = await _dio.get('/service-providers',
        queryParameters: {'scope': 'area', 'areaId': areaId, 'pageSize': pageSize});
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

  Future<List<WorkshopItem>> events({String? q}) async {
    final res = await _dio.get('/events',
        queryParameters: {'pageSize': 50, if (q != null && q.isNotEmpty) 'q': q});
    return (res.data['data'] as List)
        .map((e) => WorkshopItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Workshops/events narrowed to a single picked area — powers the Home feed's
  /// "Workshops in X ▾" section header when a per-section area is chosen.
  Future<Section<WorkshopItem>> eventsScoped(int areaId, {int pageSize = 6}) async {
    final res =
        await _dio.get('/events', queryParameters: {'scope': 'area', 'areaId': areaId, 'pageSize': pageSize});
    return Section(
      total: (res.data['meta']['total'] as num).toInt(),
      items: (res.data['data'] as List).map((e) => WorkshopItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<List<GroupItem>> groups({String? q}) async {
    final res = await _dio.get('/groups',
        queryParameters: {'pageSize': 50, if (q != null && q.isNotEmpty) 'q': q});
    return (res.data['data'] as List)
        .map((e) => GroupItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Groups narrowed to a single picked area — powers the Home feed's "Groups in X ▾"
  /// section header when a per-section area is chosen.
  Future<Section<GroupItem>> groupsScoped(int areaId, {int pageSize = 6}) async {
    final res =
        await _dio.get('/groups', queryParameters: {'scope': 'area', 'areaId': areaId, 'pageSize': pageSize});
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

  /// Uploads an image to the shared media endpoint and returns its URL.
  Future<String> uploadImage(String filePath) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(filePath)});
    final res = await _dio.post('/media', data: form);
    return res.data['data']['url'] as String;
  }

  // ── Groups lifecycle ───────────────────────────────────────
  Future<GroupDetail> group(int id) async {
    final res = await _dio.get('/groups/$id');
    return GroupDetail.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> joinGroup(int id) async => _dio.post('/groups/$id/join');
  Future<void> leaveGroup(int id) async => _dio.post('/groups/$id/leave');

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
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>((ref) {
  return DiscoveryRepository(ref.watch(dioProvider));
});

final serviceProvidersProvider = FutureProvider<List<ServiceProviderItem>>((ref) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).serviceProviders();
});

final eventsProvider = FutureProvider<List<WorkshopItem>>((ref) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).events();
});

final groupsProvider = FutureProvider<List<GroupItem>>((ref) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).groups();
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

/// Service providers/events/groups for a single picked area, keyed by areaId — backs the
/// Home feed's per-section area overrides (see `home/data/home_repository.dart`'s
/// `SectionAreaOverride` providers).
final spSectionScopedProvider = FutureProvider.family<Section<ServiceProviderItem>, int>((ref, areaId) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).serviceProvidersScoped(areaId);
});
final workshopsSectionScopedProvider = FutureProvider.family<Section<WorkshopItem>, int>((ref, areaId) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).eventsScoped(areaId);
});
final groupsSectionScopedProvider = FutureProvider.family<Section<GroupItem>, int>((ref, areaId) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).groupsScoped(areaId);
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

/// A member's public profile, keyed by profile id.
final publicProfileProvider = FutureProvider.family<PublicProfile, int>((ref, id) {
  ref.bindToAccount();
  return ref.watch(discoveryRepositoryProvider).publicProfile(id);
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
