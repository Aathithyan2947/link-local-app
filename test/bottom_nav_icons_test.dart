import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BUG-078: the Figma bottom bar draws every tab with a filled glyph (Home, Services, Events,
/// Groups); only the colour shows which tab is active. Outlined glyphs read as "unfilled".
void main() {
  test('every bottom-bar tab uses one filled icon, whichever tab is active', () {
    final src = File('lib/features/home/presentation/home_shell.dart').readAsStringSync();
    final items =
        RegExp(r'_NavItem\(\s*(icon:.*?onTap: \w+,)', dotAll: true).allMatches(src).map((m) => m.group(1)!).toList();
    expect(items, hasLength(4), reason: 'Home, Services, Events, Groups');

    for (final item in items) {
      final label = RegExp(r"label: '([^']+)'").firstMatch(item)!.group(1);
      final icon = RegExp(r'\bicon: (Icons\.\w+)').firstMatch(item)!.group(1);
      expect(icon, isNot(contains('_outline')), reason: '$label is outlined');
      expect(item, isNot(contains('activeIcon')), reason: '$label swaps glyphs; the Figma only changes colour');
    }
  });
}
