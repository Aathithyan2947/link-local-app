import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'product_models.dart';

/// Service-provider business management: their own product catalogue.
class BusinessRepository {
  BusinessRepository(this._dio);
  final Dio _dio;

  Future<List<SpProduct>> myProducts() async {
    final res = await _dio.get('/profiles/me/products');
    return (res.data['data'] as List)
        .map((e) => SpProduct.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createProduct(Map<String, dynamic> data) async => _dio.post('/profiles/me/products', data: data);
  Future<void> updateProduct(int id, Map<String, dynamic> data) async =>
      _dio.patch('/profiles/me/products/$id', data: data);
  Future<void> deleteProduct(int id) async => _dio.delete('/profiles/me/products/$id');

  Future<String> uploadImage(String filePath) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(filePath)});
    final res = await _dio.post('/media', data: form);
    return res.data['data']['url'] as String;
  }
}

final businessRepositoryProvider =
    Provider<BusinessRepository>((ref) => BusinessRepository(ref.watch(dioProvider)));

/// The current SP's own product list.
final myProductsProvider =
    FutureProvider<List<SpProduct>>((ref) => ref.watch(businessRepositoryProvider).myProducts());
