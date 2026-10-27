import 'package:shared_preferences/shared_preferences.dart';

/// Whether an account created on this device has yet to pick Resident or Service Provider.
///
/// The address is saved before the role step, so the server alone can't tell a resident who
/// finished sign-up from someone who quit on the proof or role screen (both are `resident` with
/// an address), and the router used to send the latter straight home (BUG-095). Set when the
/// account is created, cleared once a role is saved. Kept per account in shared preferences, so
/// signing in again on this device resumes at the role step; another device can't know.
///
/// A provider who quits on the services step is caught server-side instead (no services).
abstract final class SignupProgress {
  static String _key(int userId) => 'll_signup_unfinished_$userId';

  static Future<bool> isUnfinished(int userId) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key(userId)) ?? false;
    } catch (_) {
      return false; // unreadable storage: never trap anyone in sign-up
    }
  }

  static Future<void> markUnfinished(int userId) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key(userId), true);
    } catch (_) {
      // Best effort: the worst case is the old behaviour, landing on Home.
    }
  }

  static Future<void> clear(int userId) async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key(userId));
    } catch (_) {}
  }
}
