import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';

/// Provides a configured [Dio] instance with auth + refresh interceptors.
final dioProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      // Generous timeouts so the first request can ride out a hosted backend
      // cold-start (free tiers can take ~30-60s to wake from idle).
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 60),
      contentType: 'application/json',
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await tokenStorage.accessToken;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Cold-start tolerance: retry once on a connection/timeout error so the
        // first request after the backend wakes from idle doesn't surface as a failure.
        if ((error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.connectionError) &&
            error.requestOptions.extra['timeoutRetried'] != true) {
          final req = error.requestOptions;
          req.extra['timeoutRetried'] = true;
          try {
            final response = await dio.fetch(req);
            return handler.resolve(response);
          } catch (_) {
            // fall through to surface the original error
          }
        }
        // Attempt a single refresh on 401, then retry the original request.
        if (error.response?.statusCode == 401 &&
            error.requestOptions.extra['retried'] != true) {
          final refreshed = await _tryRefresh(dio, tokenStorage);
          if (refreshed) {
            final req = error.requestOptions;
            req.extra['retried'] = true;
            final newToken = await tokenStorage.accessToken;
            req.headers['Authorization'] = 'Bearer $newToken';
            try {
              final response = await dio.fetch(req);
              return handler.resolve(response);
            } catch (_) {
              // fall through
            }
          }
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});

Future<bool> _tryRefresh(Dio dio, TokenStorage storage) async {
  final refresh = await storage.refreshToken;
  if (refresh == null || refresh.isEmpty) return false;
  try {
    final raw = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 60),
    ));
    final res = await raw.post('/auth/refresh', data: {'refreshToken': refresh});
    final access = res.data['data']?['accessToken'] as String?;
    if (access != null) {
      await storage.saveAccess(access);
      return true;
    }
  } catch (_) {}
  return false;
}
