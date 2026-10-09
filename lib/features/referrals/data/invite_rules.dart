import 'package:flutter/services.dart';

/// The invite form's rules — the server checks the same ones (referrals.routes.ts).

const kInviteNameMax = 50;

/// 10 plain digits from whatever was typed or pasted: drops spaces, dashes and a leading
/// +91, 91 or 0.
String normalizeIndianMobile(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) return digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) return digits.substring(1);
  return digits;
}

/// Null when [raw] is a valid Indian mobile (10 digits starting 6–9).
String? inviteMobileError(String raw) =>
    RegExp(r'^[6-9]\d{9}$').hasMatch(normalizeIndianMobile(raw)) ? null : 'Enter a valid 10-digit mobile number';

/// Null when the (optional) name is fine: letters, spaces and . ' - only, at most 50.
String? inviteNameError(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return null;
  if (name.length > kInviteNameMax) return 'Name can be at most $kInviteNameMax characters';
  if (!RegExp(r"^[\p{L}\p{M} .'-]+$", unicode: true).hasMatch(name)) return 'Name can have letters and spaces only';
  return null;
}

/// "98765 43210" — how a saved number is shown.
String formatIndianMobile(String phone) {
  final d = normalizeIndianMobile(phone);
  return d.length == 10 ? '${d.substring(0, 5)} ${d.substring(5)}' : phone;
}

/// Keeps the mobile field to 10 digits: typing stops there, and a pasted "+91 98765-43210"
/// lands as 9876543210.
class IndianMobileInputFormatter extends TextInputFormatter {
  const IndianMobileInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    // Only a paste (more than one character added) can bring a country code with it.
    final pasted = newValue.text.length - oldValue.text.length > 1;
    if (pasted && digits.length > 10) digits = normalizeIndianMobile(digits);
    if (digits.length > 10) digits = digits.substring(0, 10);
    return TextEditingValue(text: digits, selection: TextSelection.collapsed(offset: digits.length));
  }
}
