import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/push_guard.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_models.dart';
import '../data/address_models.dart';
import '../data/address_repository.dart';
import 'address_proof_screen.dart';

/// Ordering, joining, posting, creating, reviewing, liking and commenting need an address proof
/// first (BUG-084): an uploaded one, even if it's still under review, or an admin's verification.
/// Only those actions are held back, never the account: browsing, chat, profile edits and the
/// upload itself stay open. The server
/// enforces it (403 `ADDRESS_PROOF_REQUIRED`); these helpers ask up front, so the member gets
/// the "Address proof mandatory" popup instead of a failed action.
///
/// [action] completes "Upload your address proof to …", e.g. "submit a review".

/// True when the member may go ahead. Otherwise shows the popup and returns false. When the
/// proof status can't be loaded it returns true and leaves the decision to the server.
Future<bool> ensureAddressProof(BuildContext context, WidgetRef ref, {required String action}) async {
  if (await hasAddressProof(ref)) return true;
  if (context.mounted) await showAddressProofRequired(context, action: action);
  return false;
}

/// The check alone, for a screen that shows a busy button while it runs and the popup only
/// after (a spinner behind the popup reads as still working).
Future<bool> hasAddressProof(WidgetRef ref) async {
  if (ref.read(authControllerProvider).user?.isVerified == true) return true;
  final status = await _proofStatus(ref);
  return status == null || status == 'pending' || status == 'approved';
}

/// The member's proof status, or null if it can't be loaded. Settles on the first error: a
/// failed load is retried in the background, and `.future` would wait through every retry,
/// leaving the tapped button doing nothing for seconds when offline.
Future<String?> _proofStatus(WidgetRef ref) async {
  final result = Completer<String?>();
  final sub = ref.listenManual<AsyncValue<AddressProofInfo>>(myAddressProofProvider, (_, next) {
    if (result.isCompleted) return;
    if (next.hasValue) {
      result.complete(next.requireValue.status);
    } else if (next.hasError) {
      result.complete(null);
    }
  }, fireImmediately: true);
  try {
    return await result.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
  } finally {
    sub.close();
  }
}

/// For an instant action (a like): decides from the status already loaded, so a heart never
/// waits on the network, and shows the popup when the proof is known to be missing. A status
/// not loaded yet counts as allowed; the server still refuses, and the caller's error handler
/// shows the popup then ([handleAddressProofError]).
bool checkAddressProofNow(BuildContext context, WidgetRef ref, {required String action}) {
  final missing = addressProofKnownMissing(ref);
  if (missing) showAddressProofRequired(context, action: action);
  return !missing;
}

/// Whether the proof is known to be missing right now, without asking anything.
bool addressProofKnownMissing(WidgetRef ref) =>
    _knownMissing(ref.read(myAddressProofProvider).value, ref.read(authControllerProvider).user);

/// For a widget that should look blocked as it builds (the comment box): whether the proof is
/// known to be missing. Rebuilds once a proof is uploaded.
bool watchAddressProofMissing(WidgetRef ref) =>
    _knownMissing(ref.watch(myAddressProofProvider).value, ref.watch(authControllerProvider).user);

bool _knownMissing(AddressProofInfo? info, AppUser? user) =>
    user?.isVerified != true && info != null && info.status != 'pending' && info.status != 'approved';

/// Opens [page] when the member may [action]; otherwise shows the popup instead.
Future<T?> pushIfAddressProof<T extends Object?>(
  BuildContext context,
  WidgetRef ref, {
  required String action,
  required WidgetBuilder page,
}) async {
  if (!await ensureAddressProof(context, ref, action: action)) return null;
  if (!context.mounted) return null;
  return context.pushPage<T>(MaterialPageRoute(builder: page));
}

/// For a catch block: when the server refused for want of a proof, shows the popup and
/// returns true; otherwise false, and the caller reports [error] as usual.
bool handleAddressProofError(BuildContext context, Object error, {required String action}) {
  if (ApiException.from(error).code != ApiException.addressProofRequired) return false;
  if (context.mounted) showAddressProofRequired(context, action: action);
  return true;
}

/// The popup; "Upload address proof" opens the upload screen.
Future<void> showAddressProofRequired(BuildContext context, {required String action}) async {
  final upload = await showDialog<bool>(
    context: context,
    builder: (_) => AddressProofRequiredDialog(action: action),
  );
  if (upload == true && context.mounted) {
    await context.pushPage(MaterialPageRoute(builder: (_) => const AddressProofScreen()));
  }
}

/// "Address proof mandatory" — the Figma popup.
class AddressProofRequiredDialog extends StatelessWidget {
  const AddressProofRequiredDialog({super.key, required this.action});
  final String action;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.18), shape: BoxShape.circle),
              child: const Icon(Icons.location_on, size: 42, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text(
              'Address proof mandatory',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: AppColors.ink),
            ),
            const SizedBox(height: 14),
            Text(
              'Upload your address proof to $action.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: 'Upload address proof', onPressed: () => Navigator.pop(context, true)),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary, minimumSize: const Size.fromHeight(44)),
              child: const Text('Not now', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}
