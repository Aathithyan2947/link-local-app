import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';

/// A dynamic field configured for a service subcategory (admin-defined). `value` is the SP's
/// current answer — plain text, or an uploaded file URL for the 'file' type (menu/rate card).
class CustomField {
  CustomField({
    required this.fieldId,
    required this.subcategoryName,
    required this.fieldName,
    required this.fieldType,
    required this.isRequired,
    this.fieldOptions,
    this.value,
  });

  final int fieldId;
  final String subcategoryName;
  final String fieldName;
  final String fieldType; // text | number | date | dropdown | boolean | file
  final bool isRequired;
  final String? fieldOptions; // JSON array string for dropdown
  String? value;

  factory CustomField.fromJson(Map<String, dynamic> j) => CustomField(
        fieldId: j['fieldId'] as int,
        subcategoryName: j['subcategoryName'] as String? ?? '',
        fieldName: j['fieldName'] as String? ?? '',
        fieldType: j['fieldType'] as String? ?? 'text',
        isRequired: j['isRequired'] as bool? ?? false,
        fieldOptions: j['fieldOptions'] as String?,
        value: j['value'] as String?,
      );
}

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

  /// Dynamic fields for the SP's selected subcategories (incl. their saved values).
  Future<List<CustomField>> getCustomFields() async {
    try {
      final res = await _dio.get('/profiles/me/custom-fields');
      return ((res.data['data'] as List?) ?? [])
          .map((e) => CustomField.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> saveCustomFields(List<Map<String, dynamic>> values) async {
    try {
      await _dio.put('/profiles/me/custom-fields', data: {'values': values});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Uploads a file (e.g. menu/rate card) and returns its stored URL.
  Future<String> uploadCustomFieldFile(Uint8List bytes, String filename) async {
    try {
      final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)});
      final res = await _dio.post('/profiles/me/custom-fields/upload', data: form);
      return res.data['data']['url'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final serviceProfileRepositoryProvider = Provider<ServiceProfileRepository>((ref) {
  return ServiceProfileRepository(ref.watch(dioProvider));
});

final customFieldsProvider = FutureProvider<List<CustomField>>((ref) {
  return ref.watch(serviceProfileRepositoryProvider).getCustomFields();
});
