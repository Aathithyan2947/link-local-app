import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'profile_models.dart';

class ProfileRepository {
  ProfileRepository(this._dio);
  final Dio _dio;

  Future<T> _wrap<T>(Future<Response> Function() call, T Function(dynamic data) map) async {
    try {
      final res = await call();
      return map(res.data is Map ? res.data['data'] : res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<ProfileDetail> getMyProfile() =>
      _wrap(() => _dio.get('/profiles/me'), (d) => ProfileDetail.fromJson(d as Map<String, dynamic>));

  Future<void> updateBasic(Map<String, dynamic> data) =>
      _wrap(() => _dio.patch('/profiles/me', data: data), (_) {});

  Future<void> uploadPhoto(Uint8List bytes, String filename) => _wrap(
        () => _dio.post('/profiles/me/photo',
            data: FormData.fromMap({'photo': MultipartFile.fromBytes(bytes, filename: filename)})),
        (_) {},
      );

  Future<void> addEducation(Map<String, dynamic> data) =>
      _wrap(() => _dio.post('/profiles/me/education', data: data), (_) {});

  Future<void> addProfession(Map<String, dynamic> data) =>
      _wrap(() => _dio.post('/profiles/me/professions', data: data), (_) {});

  Future<void> addHobby(Map<String, dynamic> data) =>
      _wrap(() => _dio.post('/profiles/me/hobbies', data: data), (_) {});

  Future<void> addFamily(Map<String, dynamic> data) =>
      _wrap(() => _dio.post('/profiles/me/family', data: data), (_) {});

  Future<void> addPet(Map<String, dynamic> data) =>
      _wrap(() => _dio.post('/profiles/me/pets', data: data), (_) {});

  Future<void> addContact(Map<String, dynamic> data) =>
      _wrap(() => _dio.post('/profiles/me/contacts', data: data), (_) {});

  Future<void> addProduct(Map<String, dynamic> data) =>
      _wrap(() => _dio.post('/profiles/me/products', data: data), (_) {});

  Future<void> setDelivery(Map<String, dynamic> data) =>
      _wrap(() => _dio.put('/profiles/me/delivery', data: data), (_) {});

  Future<String> suggestOfferHelp() => _wrap(
        () => _dio.get('/profiles/me/offer-help/suggest'),
        (d) => (d as Map<String, dynamic>)['suggestion'] as String? ?? '',
      );

  /// section: education | professions | hobbies | family | pets | contacts | products
  Future<void> deleteItem(String section, int id) =>
      _wrap(() => _dio.delete('/profiles/me/$section/$id'), (_) {});

  Future<List<IdName>> professions() => _wrap(
        () => _dio.get('/masters/professions', queryParameters: {'pageSize': 100}),
        (d) => (d as List).map((e) => IdName(e['id'] as int, e['category'] as String)).toList(),
      );

  Future<List<IdName>> hobbies() => _wrap(
        () => _dio.get('/masters/hobbies', queryParameters: {'pageSize': 100, 'isActive': 'true'}),
        (d) => (d as List).map((e) => IdName(e['id'] as int, e['name'] as String)).toList(),
      );
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(dioProvider));
});

final myProfileProvider = FutureProvider<ProfileDetail>((ref) {
  return ref.watch(profileRepositoryProvider).getMyProfile();
});

final professionMasterProvider = FutureProvider<List<IdName>>((ref) {
  return ref.watch(profileRepositoryProvider).professions();
});

final hobbyMasterProvider = FutureProvider<List<IdName>>((ref) {
  return ref.watch(profileRepositoryProvider).hobbies();
});
