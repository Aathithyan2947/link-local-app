import '../../../core/auth/auth_scope.dart';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'address_models.dart';

class AddressRepository {
  AddressRepository(this._dio);
  final Dio _dio;

  /// Directory autocomplete (curated Address Master localities) from the backend.
  Future<DirectoryResults> searchDirectory(String q) async {
    try {
      final res = await _dio.get('/addresses/directory', queryParameters: {'q': q});
      final data = res.data['data'] as Map<String, dynamic>;
      return DirectoryResults(
        localities: ((data['localities'] as List?) ?? [])
            .map((e) => MasterSuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Approved Address Master localities within ~2 km of a GPS pin, nearest first.
  /// This is the primary, curated source for autofilling lane/area/suburb/city/pincode.
  Future<List<MasterSuggestion>> nearbyMaster(double lat, double lng) async {
    try {
      final res = await _dio.get('/addresses/nearby', queryParameters: {'lat': lat, 'lng': lng});
      return ((res.data['data'] as List?) ?? [])
          .map((e) => MasterSuggestion.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Reverse-geocode a map pin through the backend, which holds the Google key and
  /// caches every result. Used only as a FALLBACK when no curated Address Master
  /// locality is nearby — the curated data stays the source of truth.
  ///
  /// Never throws: a failed lookup falls back to bare coordinates rather than
  /// dead-ending the address flow, exactly as the previous geocoder did.
  Future<GeoAddress> reverseGeocode(double lat, double lng) async {
    try {
      final res = await _dio.get('/geo/reverse', queryParameters: {'lat': lat, 'lng': lng});
      return GeoAddress.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException {
      return GeoAddress(latitude: lat, longitude: lng);
    }
  }

  Future<void> createAddress({
    required int cityId,
    required String fullAddress,
    String? areaName,
    String? pincode,
    String? apartment,
    String? flatWing,
    String? suburb,
    String? lane1,
    String? lane2,
    double? latitude,
    double? longitude,
    double? accuracyM,
    String? locationSource,
    String? googlePlaceId,
  }) async {
    try {
      await _dio.post('/addresses', data: {
        'cityId': cityId,
        'fullAddress': fullAddress,
        if (areaName != null && areaName.isNotEmpty) 'areaName': areaName,
        if (pincode != null && pincode.isNotEmpty) 'pincode': pincode,
        if (apartment != null && apartment.isNotEmpty) 'apartment': apartment,
        if (flatWing != null && flatWing.isNotEmpty) 'flatWing': flatWing,
        if (suburb != null && suburb.isNotEmpty) 'suburb': suburb,
        if (lane1 != null && lane1.isNotEmpty) 'lane1': lane1,
        if (lane2 != null && lane2.isNotEmpty) 'lane2': lane2,
        // The user's chosen pin — stored privately AND used to give a new master
        // locality its coordinates (so it works in 2 km autofill once approved).
        'latitude': ?latitude,
        'longitude': ?longitude,
        // How the pin was captured, so a bad one can be found and re-verified
        // later instead of being indistinguishable from a surveyed doorstep.
        'accuracyM': ?accuracyM,
        'locationSource': ?locationSource,
        'googlePlaceId': ?googlePlaceId,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Current user's address + proof verification status.
  Future<AddressProofInfo> getMyAddressProof() async {
    try {
      final res = await _dio.get('/addresses/me');
      return AddressProofInfo.fromAddressJson(res.data['data'] as Map<String, dynamic>?);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Per-city address-form field configuration (visible fields only).
  Future<List<CityAddressField>> getCityAddressFields(int cityId) async {
    try {
      final res = await _dio.get('/addresses/city-fields/$cityId');
      return (res.data['data'] as List)
          .map((e) => CityAddressField.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> uploadProof({
    required Uint8List bytes,
    required String filename,
    required String docType,
    String? description,
  }) async {
    try {
      final form = FormData.fromMap({
        'docType': docType,
        if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
        'document': MultipartFile.fromBytes(bytes, filename: filename),
      });
      await _dio.post('/addresses/documents', data: form);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Records how the member heard about us + who referred them (member ID / referral code).
  /// Throws with a clear message if the referral code is invalid.
  Future<void> setReferral({String? referralCode, int? referralSourceId}) async {
    try {
      await _dio.patch('/profiles/me/referral', data: {
        if (referralCode != null && referralCode.trim().isNotEmpty) 'referralCode': referralCode.trim(),
        'referralSourceId': ?referralSourceId,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final addressRepositoryProvider = Provider<AddressRepository>((ref) {
  return AddressRepository(ref.watch(dioProvider));
});

final myAddressProofProvider = FutureProvider<AddressProofInfo>((ref) {
  ref.bindToAccount();
  return ref.watch(addressRepositoryProvider).getMyAddressProof();
});
