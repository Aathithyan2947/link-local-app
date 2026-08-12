import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/auth/auth_scope.dart';

const _storage = FlutterSecureStorage();

/// Keyed per account. A single global key would carry the flag across a logout, so a brand-new
/// member on a shared device would inherit "already congratulated" from whoever used it before.
String _key(int userId) => 'll_profile_congrats_shown_$userId';

/// Whether the one-time "your profile is complete" congratulations banner has already been
/// shown (and its 10s auto-dismiss has elapsed). Once shown, it never shows again — mirrors
/// `doc_reminder.dart`'s dismissed-flag pattern.
///
/// Reads `true` while logged out so nothing tries to congratulate a signed-out session.
final profileCongratsShownProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(authScopeProvider);
  if (userId == null) return true;
  return (await _storage.read(key: _key(userId))) == '1';
});

Future<void> markProfileCongratsShown(WidgetRef ref) async {
  final userId = ref.read(authScopeProvider);
  if (userId == null) return;
  await _storage.write(key: _key(userId), value: '1');
  ref.invalidate(profileCongratsShownProvider);
}
