import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/profile_repository.dart';
import '../login_security_screen.dart';

/// Which public contact detail a [showContactFieldEditor] sheet edits.
enum ContactField {
  phone('servicePhone'),
  email('serviceEmail');

  const ContactField(this.apiKey);

  /// The `PATCH /profiles/me` field it writes.
  final String apiKey;
}

/// Edits the public Mobile or Email shown in the profile's Contact info — never the
/// sign-in credentials, which keep their OTP-protected screens in Login & Security.
///
/// [current] is the saved public value (empty when none is set); [signInValue] is what
/// neighbours see instead while it's empty. [afterSave] runs before the sheet closes,
/// so the new value is already on screen when it does. Resolves true when saved.
Future<bool> showContactFieldEditor(
  BuildContext context, {
  required ContactField field,
  String? current,
  String? signInValue,
  Future<void> Function()? afterSave,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ContactFieldSheet(
      field: field,
      current: current ?? '',
      signInValue: signInValue,
      afterSave: afterSave,
    ),
  );
  return saved ?? false;
}

final _phonePattern = RegExp(r'^[0-9]{10}$');
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Null when [value] is acceptable for [field]; empty always is (it clears the field).
String? validateContactField(ContactField field, String value) {
  if (value.isEmpty) return null;
  return switch (field) {
    ContactField.phone => _phonePattern.hasMatch(value) ? null : 'Enter a valid 10-digit mobile number',
    ContactField.email => _emailPattern.hasMatch(value) ? null : 'Enter a valid email address',
  };
}

class _ContactFieldSheet extends ConsumerStatefulWidget {
  const _ContactFieldSheet({required this.field, required this.current, this.signInValue, this.afterSave});
  final ContactField field;
  final String current;
  final String? signInValue;
  final Future<void> Function()? afterSave;

  @override
  ConsumerState<_ContactFieldSheet> createState() => _ContactFieldSheetState();
}

class _ContactFieldSheetState extends ConsumerState<_ContactFieldSheet> {
  late final _ctrl = TextEditingController(text: widget.current);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isPhone => widget.field == ContactField.phone;

  Future<void> _save() async {
    final value = _ctrl.text.trim();
    final problem = validateContactField(widget.field, value);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (value == widget.current.trim()) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // An empty string clears it, falling back to the sign-in value.
      await ref.read(profileRepositoryProvider).updateBasic({widget.field.apiKey: value});
      ref.invalidate(myProfileProvider);
      try {
        await widget.afterSave?.call();
      } catch (_) {
        // Saved regardless; the screen refreshes itself on its next load.
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  void _openLoginSecurity() {
    final navigator = Navigator.of(context);
    navigator.pop(false);
    navigator.push(MaterialPageRoute(builder: (_) => const LoginSecurityScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final fallback = widget.signInValue?.trim() ?? '';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_isPhone ? 'Edit mobile number' : 'Edit email', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Shown to neighbours on your profile.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          // Configured exactly like the login screen's phone/email fields, which take typing
          // reliably: no autofocus while the sheet animates in, no autocorrect override,
          // and email left unfiltered (it's trimmed on save instead).
          TextField(
            controller: _ctrl,
            keyboardType: _isPhone ? TextInputType.phone : TextInputType.emailAddress,
            maxLength: _isPhone ? 10 : null,
            inputFormatters: _isPhone ? [FilteringTextInputFormatter.digitsOnly] : null,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            decoration: InputDecoration(
              hintText: _isPhone ? '10-digit mobile number' : 'name@example.com',
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
          if (fallback.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Leave empty to show your sign-in ${_isPhone ? 'number' : 'email'} ($fallback).',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'To change the ${_isPhone ? 'number' : 'email'} you sign in with:',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
              TextButton(onPressed: _saving ? null : _openLoginSecurity, child: const Text('Login & Security')),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
