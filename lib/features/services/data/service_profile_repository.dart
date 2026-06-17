import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';

class ServiceProfileRepository {
  ServiceProfileRepository(this._dio);
  final Dio _dio;

  /// Replaces the current SP's selected service subcategories. `customServices` are free-text
  /// "Other" services ({categoryId, name}) that the backend queues for admin approval.
  Future<void> saveServiceTypes(
    List<int> subcategoryIds, {
    List<Map<String, dynamic>> customServices = const [],
  }) async {
    try {
      await _dio.post('/profiles/me/service-types', data: {
        'subcategoryIds': subcategoryIds,
        if (customServices.isNotEmpty) 'customServices': customServices,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final serviceProfileRepositoryProvider = Provider<ServiceProfileRepository>((ref) {
  return ServiceProfileRepository(ref.watch(dioProvider));
});
