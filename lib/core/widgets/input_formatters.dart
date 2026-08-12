import 'package:flutter/services.dart';

/// Input formatters for the app's numeric fields.
///
/// `TextInputType.number` only chooses a keyboard — it does not restrict what can be typed,
/// and pasted text bypasses it entirely. These enforce the shape the API actually accepts:
/// fields the backend parses as `z.number().int()` take digits only, everything else (money,
/// distances) allows a decimal point.

/// Digits only — for counts, ages, years and minutes.
final List<TextInputFormatter> kIntegerInput = [FilteringTextInputFormatter.digitsOnly];

/// Digits with at most [decimals] places.
///
/// Validates the whole resulting string rather than filtering character by character, so
/// "1.2.3" and "12.345" are rejected outright instead of being silently mangled.
class DecimalInputFormatter extends TextInputFormatter {
  DecimalInputFormatter({this.decimals = 2});

  final int decimals;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final pattern = RegExp(r'^\d*\.?\d{0,' + decimals.toString() + r'}$');
    return pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// Money and measurements — the backend takes these as plain `number`.
final List<TextInputFormatter> kDecimalInput = [DecimalInputFormatter()];

/// Pairs with [kDecimalInput]: `TextInputType.number` renders a keypad with no decimal point
/// on iOS, which would make a decimal price impossible to type.
const TextInputType kDecimalKeyboard = TextInputType.numberWithOptions(decimal: true);
