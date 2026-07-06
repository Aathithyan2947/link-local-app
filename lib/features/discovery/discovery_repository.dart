import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../home/data/home_models.dart';
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

  Future<ServiceProviderDetail> serviceProvider(int id) async {
    final res = await _dio.get('/service-providers/$id');
    return ServiceProviderDetail.fromJson(res.data['data'] as Map<String, dynamic>);
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

  Future<List<GroupItem>> groups({String? q}) async {
    final res = await _dio.get('/groups',
        queryParameters: {'pageSize': 50, if (q != null && q.isNotEmpty) 'q': q});
    return (res.data['data'] as List)
        .map((e) => GroupItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>((ref) {
  return DiscoveryRepository(ref.watch(dioProvider));
});

final serviceProvidersProvider =
    FutureProvider<List<ServiceProviderItem>>((ref) => ref.watch(discoveryRepositoryProvider).serviceProviders());

final eventsProvider =
    FutureProvider<List<WorkshopItem>>((ref) => ref.watch(discoveryRepositoryProvider).events());

final groupsProvider =
    FutureProvider<List<GroupItem>>((ref) => ref.watch(discoveryRepositoryProvider).groups());

/// Full service-provider profile, keyed by profile id.
final serviceProviderDetailProvider =
    FutureProvider.family<ServiceProviderDetail, int>((ref, id) =>
        ref.watch(discoveryRepositoryProvider).serviceProvider(id));

/// Shared search query for the Discover screen — lists are filtered client-side
/// so tab counts and results update live as the user types.
class DiscoverQuery extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}

final discoverQueryProvider = NotifierProvider<DiscoverQuery, String>(DiscoverQuery.new);

/// Active Discover tab: 0 = All, 1 = Events, 2 = Service Providers, 3 = Groups.
/// Shared so the bottom nav (Services/Events/Groups) and the in-screen tab row
/// stay in sync.
class DiscoverTab extends Notifier<int> {
  @override
  int build() => 0;
  void set(int value) => state = value;
}

final discoverTabProvider = NotifierProvider<DiscoverTab, int>(DiscoverTab.new);
