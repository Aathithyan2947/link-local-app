import 'package:dio/dio.dart';

/// Normalised API error with a user-presentable message.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.details});

  final String message;
  final int? statusCode;
  final Object? details;

  factory ApiException.fromDio(DioException e) {
    final response = e.response;
    if (response != null) {
      final data = response.data;
      String message = 'Something went wrong';
      if (data is Map && data['message'] is String) {
        message = data['message'] as String;
      }
      return ApiException(
        message,
        statusCode: response.statusCode,
        details: data is Map ? data['details'] : null,
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return ApiException('Cannot reach the server. Check your connection.');
    }
    return ApiException(e.message ?? 'Unexpected network error');
  }

  @override
  String toString() => message;
}
