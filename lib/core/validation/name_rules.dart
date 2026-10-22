import 'package:flutter/services.dart';

import '../../features/business/data/profile_limits.dart';

/// Sign-up name rule: letters in any language plus spaces and . ' - (no digits or symbols),
/// 2–100 characters. The backend's `nameField` (auth.schema.ts) uses the same rule and the
/// same messages, so a name the app accepts is never rejected by the server.
abstract final class NameRules {
  static const max = ProfileLimits.name;
  static const min = 2;

  static final _allowedChar = RegExp(r"[\p{L}\p{M} .'\-]", unicode: true);
  static final _valid = RegExp(r"^[\p{L}\p{M}][\p{L}\p{M} .'\-]*$", unicode: true);

  /// Drops digits and symbols as they're typed or pasted.
  static final inputFormatter = FilteringTextInputFormatter.allow(_allowedChar);

  static String? error(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'Enter your name';
    if (v.length < min) return 'Name must be at least $min characters';
    if (v.length > max) return 'Name can be at most $max characters';
    if (!_valid.hasMatch(v)) return "Name can only contain letters, spaces and . ' -";
    return null;
  }
}
