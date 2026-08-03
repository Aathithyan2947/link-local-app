import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kShown = 'll_profile_congrats_shown';
const _storage = FlutterSecureStorage();

/// Whether the one-time "your profile is complete" congratulations banner has already been
/// shown (and its 10s auto-dismiss has elapsed). Once shown, it never shows again — mirrors
/// `doc_reminder.dart`'s dismissed-flag pattern.
final profileCongratsShownProvider = FutureProvider<bool>((ref) async {
  return (await _storage.read(key: _kShown)) == '1';
});

Future<void> markProfileCongratsShown(WidgetRef ref) async {
  await _storage.write(key: _kShown, value: '1');
  ref.invalidate(profileCongratsShownProvider);
}
