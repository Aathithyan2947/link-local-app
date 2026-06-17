/// App-wide configuration. The API base URL can be overridden at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:4000/api/v1
abstract class AppConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    // Hosted backend (Render). For local dev, override at build time:
    //   flutter run --dart-define=API_BASE_URL=http://localhost:4000/api/v1
    //   (Android emulator reaches the host via 10.0.2.2.)
    return 'https://link-local-backend.onrender.com/api/v1';
  }

  /// Host root for backend-served assets (strips the `/api/v1` suffix).
  static String get _assetHost => apiBaseUrl.replaceAll('/api/v1', '');

  /// Builds an absolute URL for a backend asset path (e.g. `/uploads/x.jpg`).
  static String assetUrl(String path) =>
      path.startsWith('http') ? path : '$_assetHost$path';

  static const String appName = 'Link Local';
}
