import 'package:flutter/foundation.dart';

/// App-wide configuration. The API base URL can be overridden at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:4000/api/v1
abstract class AppConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    // Android emulator reaches the host machine via 10.0.2.2.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:4000/api/v1';
    }
    // Web (Chrome) + iOS simulator can use localhost directly.
    return 'http://localhost:4000/api/v1';
  }

  static const String appName = 'Link Local';
}
