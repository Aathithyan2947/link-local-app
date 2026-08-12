import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/auth/auth_scope.dart';

const _storage = FlutterSecureStorage();

/// Keyed per account — see the matching note in `profile_congrats.dart`. Under a single global
/// key, one member dismissing this would hide it for every later account on the device.
String _key(int userId) => 'll_doc_reminder_dismissed_$userId';

/// Whether the member permanently dismissed the "upload your address proof" home reminder.
/// We don't insist — once they skip it, it stays hidden; they can still upload from Profile.
///
/// Reads `true` while logged out so a signed-out session never shows the reminder.
final docReminderDismissedProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(authScopeProvider);
  if (userId == null) return true;
  return (await _storage.read(key: _key(userId))) == '1';
});

Future<void> dismissDocReminder(WidgetRef ref) async {
  final userId = ref.read(authScopeProvider);
  if (userId == null) return;
  await _storage.write(key: _key(userId), value: '1');
  ref.invalidate(docReminderDismissedProvider);
}
