import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'home_models.dart';

class HomeRepository {
  HomeRepository(this._dio);
  final Dio _dio;

  Future<HomeFeed> getHome() async {
    try {
      final res = await _dio.get('/home');
      return HomeFeed.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(ref.watch(dioProvider));
});

final homeFeedProvider = FutureProvider<HomeFeed>((ref) {
  return ref.watch(homeRepositoryProvider).getHome();
});
