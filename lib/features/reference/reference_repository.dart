import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import 'reference_models.dart';

class ReferenceRepository {
  ReferenceRepository(this._dio);
  final Dio _dio;

  Future<List<City>> cities() async {
    final res = await _dio.get('/masters/cities', queryParameters: {'pageSize': 100, 'isActive': 'true'});
    final list = (res.data['data'] as List).cast<Map<String, dynamic>>();
    return list.map(City.fromJson).toList();
  }

  Future<List<ServiceCategory>> serviceCategories() async {
    final res = await _dio.get('/masters/service-categories', queryParameters: {'pageSize': 100});
    final list = (res.data['data'] as List).cast<Map<String, dynamic>>();
    return list.map(ServiceCategory.fromJson).toList();
  }
}

final referenceRepositoryProvider = Provider<ReferenceRepository>((ref) {
  return ReferenceRepository(ref.watch(dioProvider));
});

final citiesProvider = FutureProvider<List<City>>((ref) {
  return ref.watch(referenceRepositoryProvider).cities();
});

final serviceCategoriesProvider = FutureProvider<List<ServiceCategory>>((ref) {
  return ref.watch(referenceRepositoryProvider).serviceCategories();
});
