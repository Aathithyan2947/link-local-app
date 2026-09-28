import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this device has been through the introduction slides — so a logout lands on
/// Login instead of replaying them. Device-wide rather than per account, and kept in
/// shared preferences so a fresh install shows the introduction again.
///
/// `null` while loading from storage; the router holds the splash screen until it resolves.
class IntroSeen extends Notifier<bool?> {
  static const _key = 'll_intro_seen';

  @override
  bool? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final seen = (await SharedPreferences.getInstance()).getBool(_key) ?? false;
      // A markSeen() that landed while loading wins.
      state ??= seen;
    } catch (_) {
      state ??= false; // unreadable storage: show the introduction rather than hang on splash
    }
  }

  Future<void> markSeen() async {
    if (state == true) return;
    state = true;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {
      // Best effort: the worst case is seeing the introduction once more.
    }
  }
}

final introSeenProvider = NotifierProvider<IntroSeen, bool?>(IntroSeen.new);
