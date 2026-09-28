import 'dart:io' show Platform;

/// App-wide configuration. The API base URL can be overridden at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:4000/api/v1
abstract class AppConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Flip to `false` to point the app back at the hosted Render backend.
  static const bool useLocalBackend = true;

  static const String _renderApiBaseUrl =
      'https://link-local-backend.onrender.com/api/v1';

  /// Local backend (`npm run dev` in link-local-backend, port 4000).
  /// The Android emulator reaches the host machine via 10.0.2.2; the iOS
  /// simulator can use localhost. For a physical device, pass your machine's
  /// LAN IP via --dart-define=API_BASE_URL=... instead.
  static String get _localApiBaseUrl => Platform.isAndroid
      ? 'http://10.0.2.2:4000/api/v1'
      : 'http://localhost:4000/api/v1';

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    return useLocalBackend ? _localApiBaseUrl : _renderApiBaseUrl;
  }

  /// Host root for backend-served assets (strips the `/api/v1` suffix).
  static String get _assetHost => apiBaseUrl.replaceAll('/api/v1', '');

  /// Builds an absolute URL for a backend asset path (e.g. `/uploads/x.jpg`).
  static String assetUrl(String path) =>
      path.startsWith('http') ? path : '$_assetHost$path';

  static const String appName = 'Link Local';
}
