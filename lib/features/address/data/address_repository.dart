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

  /// Reverse-geocode a map pin via OpenStreetMap Nominatim (no API key). Used only as a
  /// FALLBACK when no curated Address Master locality is nearby. Field mapping is
  /// deliberately conservative: a `road` is often a highway/flyover, so it seeds Lane 1
  /// only as a last resort, and suburb/city are kept distinct (not duplicated).
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

    // OSM hierarchy (fine → coarse): neighbourhood/residential → suburb → city_district →
    // city/town → state. Map each to a single, non-overlapping slot.
    final neighbourhood = (a['neighbourhood'] ?? a['residential'] ?? a['quarter']) as String?;
    final suburb = (a['suburb'] ?? a['city_district']) as String?;
    final city = (a['city'] ?? a['town'] ?? a['municipality'] ?? a['village']) as String?;
    final road = a['road'] as String?;
    // Skip obvious through-roads/flyovers as a "lane" — they're rarely the user's lane.
    final roadIsLane = road != null &&
        !RegExp(r'flyover|highway|expressway|bridge|f\.?o\.?b', caseSensitive: false).hasMatch(road);

    return GeoAddress(
      latitude: lat,
      longitude: lng,
      fullAddress: json['display_name'] as String?,
      lane1: roadIsLane ? road : null,
      locality: neighbourhood,
      // Prefer a true neighbourhood as the "area"; fall back to the OSM suburb.
      area: neighbourhood ?? suburb,
      suburb: suburb != neighbourhood ? suburb : null,
      city: city,
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
    double? latitude,
    double? longitude,
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
