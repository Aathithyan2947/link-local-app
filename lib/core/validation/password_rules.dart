/// The password policy, with the messages the backend sends (`passwordField` in
/// passwordRules.ts): sign-up, password reset and Change Password all use it.
abstract final class PasswordRules {
  static const hint =
      'At least 8 characters with an uppercase letter, a lowercase letter, a number and a special character.';

  /// What's wrong with [p], or null when it's acceptable.
  static String? error(String p) {
    if (p.length < 8) return 'Password must be at least 8 characters';
    if (p.length > 72) return 'Password can be at most 72 characters';
    if (!RegExp(r'[A-Z]').hasMatch(p)) return 'Password must include an uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(p)) return 'Password must include a lowercase letter';
    if (!RegExp(r'[0-9]').hasMatch(p)) return 'Password must include a number';
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(p)) return 'Password must include a special character';
    return null;
  }
}
