@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/navigation/push_guard.dart';

class _Page extends StatelessWidget {
  const _Page();
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Opened')));
}

void main() {
  testWidgets('rapid taps open the page once', (tester) async {
    var built = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => context.pushPage(MaterialPageRoute(builder: (_) {
            built++;
            return const _Page();
          })),
          child: const Text('menu'),
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('menu'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 30)); // mid-transition
    }
    await tester.pumpAndSettle();
    expect(built, 1);

    // Back, then a genuine tap opens it again.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    expect(built, 2);
  });

  testWidgets('a sheet that closes itself and then opens a page still works', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (ctx) => TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.pushPage(MaterialPageRoute(builder: (_) => const _Page()));
              },
              child: const Text('go'),
            ),
          ),
          child: const Text('open sheet'),
        ),
      ),
    ));
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Opened'), findsOneWidget);
  });

  test('screens push pages through pushPage, never a raw Navigator push', () {
    final raw = RegExp(r'Navigator\.of\(\w+\)\.push[<(]|Navigator\.push[<(]');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('push_guard.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (raw.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'use context.pushPage (lib/core/navigation/push_guard.dart) so a double tap opens one page');
  });
}
