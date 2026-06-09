import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'address_models.dart';

class AddressRepository {
  AddressRepository(this._dio);
  final Dio _dio;

  /// Directory autocomplete (localities + known complexes) from the backend.
  Future<DirectoryResults> searchDirectory(String q) async {
    try {
      final res = await _dio.get('/addresses/directory', queryParameters: {'q': q});
      final data = res.data['data'] as Map<String, dynamic>;
      return DirectoryResults(
        localities: ((data['localities'] as List?) ?? [])
            .map((e) => LocalitySuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        complexes: ((data['complexes'] as List?) ?? [])
            .map((e) => ComplexSuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Reverse-geocode a map pin via OpenStreetMap Nominatim (no API key).
  Future<GeoAddress> reverseGeocode(double lat, double lng) async {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&addressdetails=1',
    );
    final res = await http.get(uri, headers: {'User-Agent': 'LinkLocalApp/1.0'});
    if (res.statusCode != 200) {
      return GeoAddress(latitude: lat, longitude: lng);
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final a = (json['address'] as Map<String, dynamic>?) ?? {};
    return GeoAddress(
      latitude: lat,
      longitude: lng,
      fullAddress: json['display_name'] as String?,
      lane1: a['road'] as String?,
      locality: (a['neighbourhood'] ?? a['suburb'] ?? a['residential']) as String?,
      area: (a['suburb'] ?? a['city_district']) as String?,
      suburb: (a['city_district'] ?? a['suburb']) as String?,
      city: (a['city'] ?? a['town'] ?? a['state_district'] ?? a['village']) as String?,
      state: a['state'] as String?,
      pincode: a['postcode'] as String?,
    );
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
  }) async {
    try {
      final form = FormData.fromMap({
        'docType': docType,
        'document': MultipartFile.fromBytes(bytes, filename: filename),
      });
      await _dio.post('/addresses/documents', data: form);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final addressRepositoryProvider = Provider<AddressRepository>((ref) {
  return AddressRepository(ref.watch(dioProvider));
});

final myAddressProofProvider = FutureProvider<AddressProofInfo>((ref) {
  return ref.watch(addressRepositoryProvider).getMyAddressProof();
});
