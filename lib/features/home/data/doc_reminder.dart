import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kDismissed = 'll_doc_reminder_dismissed';
const _storage = FlutterSecureStorage();

/// Whether the member permanently dismissed the "upload your address proof" home reminder.
/// We don't insist — once they skip it, it stays hidden; they can still upload from Profile.
final docReminderDismissedProvider = FutureProvider<bool>((ref) async {
  return (await _storage.read(key: _kDismissed)) == '1';
});

Future<void> dismissDocReminder(WidgetRef ref) async {
  await _storage.write(key: _kDismissed, value: '1');
  ref.invalidate(docReminderDismissedProvider);
}
