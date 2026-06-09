import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../home/data/home_models.dart';

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
