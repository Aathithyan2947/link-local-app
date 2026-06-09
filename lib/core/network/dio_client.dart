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
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
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
    final raw = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
    final res = await raw.post('/auth/refresh', data: {'refreshToken': refresh});
    final access = res.data['data']?['accessToken'] as String?;
    if (access != null) {
      await storage.saveAccess(access);
      return true;
    }
  } catch (_) {}
  return false;
}
