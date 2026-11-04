import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/auth/auth_scope.dart';
import '../../address/data/address_repository.dart';

const _storage = FlutterSecureStorage();

/// Keyed per account — see the matching note in `profile_congrats.dart`. Under a single global
/// key, one member dismissing this would hide it for every later account on the device.
String _key(int userId) => 'll_doc_reminder_dismissed_$userId';

/// Whether the member dismissed the "upload your address proof" home reminder for their
/// current address. We don't insist — once they skip it, it stays hidden; they can still
/// upload from Profile. But a changed address needs a new proof (BUG-103), so the dismissal
/// holds for the address it was made on: the stored value is that address's id.
///
/// Reads `true` while logged out so a signed-out session never shows the reminder.
final docReminderDismissedProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(authScopeProvider);
  if (userId == null) return true;
  final addressId = (await ref.watch(myAddressProofProvider.future)).addressId;
  return addressId != null && (await _storage.read(key: _key(userId))) == '$addressId';
});

Future<void> dismissDocReminder(WidgetRef ref) async {
  final userId = ref.read(authScopeProvider);
  final addressId = ref.read(myAddressProofProvider).value?.addressId;
  if (userId == null || addressId == null) return;
  await _storage.write(key: _key(userId), value: '$addressId');
  ref.invalidate(docReminderDismissedProvider);
}
