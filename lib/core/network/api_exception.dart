import 'package:dio/dio.dart';

/// Shown whenever the app could not complete a round-trip to the server, whatever the
/// underlying transport failure was.
const String offlineMessage = 'Your internet seems to be a bit wonky.';

/// Normalised API error with a user-presentable message.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.details, this.code});

  final String message;
  final int? statusCode;
  final Object? details;

  /// The server's stable name for the error, when it sends one (e.g. [addressProofRequired]).
  final String? code;

  /// The member must upload an address proof first (BUG-084).
  static const addressProofRequired = 'ADDRESS_PROOF_REQUIRED';

  factory ApiException.fromDio(DioException e) {
    final response = e.response;
    if (response != null) {
      final data = response.data;
      String message = 'Something went wrong';
      Object? details;
      String? code;
      if (data is Map) {
        details = data['details'];
        if (data['code'] is String) code = data['code'] as String;
        if (data['message'] is String) message = data['message'] as String;
        // Prefer a specific field-level validation reason (e.g. "Please enter a valid
        // email address") over a generic "Validation failed".
        final fieldMsg = _firstFieldError(details);
        if (fieldMsg != null) message = fieldMsg;
      }
      return ApiException(message, statusCode: response.statusCode, details: details, code: code);
    }
    // No response at all: the request never reached the server, or the reply never came back.
    // Timeout, DNS failure, refused socket and bad certificate are all the same thing to the
    // person holding the phone, so they get one message instead of Dio's internal wording.
    return ApiException(offlineMessage);
  }

  /// Whatever a repository threw, as an [ApiException] — some repositories pass Dio's errors
  /// through unconverted.
  factory ApiException.from(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) return ApiException.fromDio(e);
    return ApiException('Something went wrong');
  }

  /// Each field the server rejected, with its message (zod `fieldErrors`).
  Map<String, String> get fieldErrors {
    final d = details;
    if (d is! Map) return const {};
    return {for (final key in d.keys) '$key': ?fieldError('$key')};
  }

  /// The server's message for one field (zod `fieldErrors`), so a form can show it under
  /// that field instead of a generic banner. Null when the server didn't flag the field.
  String? fieldError(String field) {
    final d = details;
    if (d is Map) {
      final v = d[field];
      if (v is List && v.isNotEmpty && v.first is String) return v.first as String;
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
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
