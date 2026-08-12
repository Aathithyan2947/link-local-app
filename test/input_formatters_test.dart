import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/widgets/input_formatters.dart';

/// Applies [f] as the field would: [old] is what's there, [now] the attempted result.
String apply(TextInputFormatter f, String old, String now) => f
    .formatEditUpdate(
      TextEditingValue(text: old, selection: TextSelection.collapsed(offset: old.length)),
      TextEditingValue(text: now, selection: TextSelection.collapsed(offset: now.length)),
    )
    .text;

void main() {
  group('DecimalInputFormatter', () {
    final f = DecimalInputFormatter();

    test('accepts whole numbers and up to two decimal places', () {
      expect(apply(f, '', '1'), '1');
      expect(apply(f, '19', '199'), '199');
      expect(apply(f, '199', '199.'), '199.');
      expect(apply(f, '199.', '199.5'), '199.5');
      expect(apply(f, '199.5', '199.50'), '199.50');
      expect(apply(f, '', '.5'), '.5');
    });

    test('rejects a third decimal place, keeping the previous value', () {
      expect(apply(f, '199.50', '199.501'), '199.50');
    });

    test('rejects a second decimal point', () {
      expect(apply(f, '1.2', '1.2.'), '1.2');
      expect(apply(f, '1.2', '1.2.3'), '1.2');
    });

    test('rejects letters and symbols, including a pasted mess', () {
      expect(apply(f, '', 'abc'), '');
      expect(apply(f, '12', '12a'), '12');
      expect(apply(f, '12', '-12'), '12');
      expect(apply(f, '199', '199,50'), '199');
      expect(apply(f, '5', '5e3'), '5');
    });

    test('allows clearing the field', () {
      expect(apply(f, '199.50', ''), '');
    });

    test('honours a custom decimal count', () {
      final three = DecimalInputFormatter(decimals: 3);
      expect(apply(three, '1.23', '1.234'), '1.234');
      expect(apply(three, '1.234', '1.2345'), '1.234');
    });
  });

  group('kIntegerInput', () {
    test('strips everything that is not a digit', () {
      final f = kIntegerInput.single;
      expect(apply(f, '', '42'), '42');
      expect(apply(f, '4', '4a'), '4');
      expect(apply(f, '4', '4.5'), '45'); // digitsOnly filters, it does not reject
      expect(apply(f, '', '-7'), '7');
    });
  });
}
