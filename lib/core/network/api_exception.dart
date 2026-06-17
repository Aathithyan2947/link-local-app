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
      Object? details;
      if (data is Map) {
        details = data['details'];
        if (data['message'] is String) message = data['message'] as String;
        // Prefer a specific field-level validation reason (e.g. "Please enter a valid
        // email address") over a generic "Validation failed".
        final fieldMsg = _firstFieldError(details);
        if (fieldMsg != null) message = fieldMsg;
      }
      return ApiException(message, statusCode: response.statusCode, details: details);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return ApiException('Cannot reach the server. Check your connection.');
    }
    return ApiException(e.message ?? 'Unexpected network error');
  }

  /// Pulls the first human-readable message out of a zod `flatten().fieldErrors`-shaped
  /// details map (`{ email: ["..."], password: ["..."] }`).
  static String? _firstFieldError(Object? details) {
    if (details is Map) {
      for (final v in details.values) {
        if (v is List && v.isNotEmpty && v.first is String) return v.first as String;
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  @override
  String toString() => message;
}
