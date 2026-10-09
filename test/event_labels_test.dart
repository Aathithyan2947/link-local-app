import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/discovery/data/event_detail_models.dart';
import 'package:link_local/features/discovery/presentation/widgets/discover_cards.dart';
import 'package:link_local/features/home/data/home_models.dart';

final _now = DateTime.now();

WorkshopItem _event({required Duration createdAgo, required bool started, double? rating}) => WorkshopItem.fromJson({
  'id': 21,
  'title': 'testing 2.0',
  'date': '2026-09-25T00:00:00.000Z',
  'createdAt': _now.subtract(createdAgo).toUtc().toIso8601String(),
  'hasStarted': started,
  'ratingAvg': rating,
  'creator': {
    'id': 67,
    'profile': {'name': 'Aathi testing'},
  },
});

Future<void> _card(WidgetTester tester, WorkshopItem e) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: SizedBox(width: 360, child: EventCard(event: e)))),
  ));
}

void main() {
  group('BUG-058: "New" means a new, upcoming event', () {
    test('the rule', () {
      expect(isNewEvent(createdAt: _now.subtract(const Duration(days: 1)), hasStarted: false), isTrue);
      expect(isNewEvent(createdAt: _now.subtract(const Duration(days: 10)), hasStarted: false), isFalse, reason: 'older than $kNewEventDays days');
      expect(isNewEvent(createdAt: _now.subtract(const Duration(days: 1)), hasStarted: true), isFalse, reason: 'already started / past');
      expect(isNewEvent(createdAt: null, hasStarted: false), isFalse);
    });

    testWidgets('an upcoming event created yesterday shows New', (tester) async {
      await _card(tester, _event(createdAgo: const Duration(days: 1), started: false));
      expect(find.text('New'), findsOneWidget);
    });

    testWidgets('a past event with no ratings does not', (tester) async {
      await _card(tester, _event(createdAgo: const Duration(days: 1), started: true));
      expect(find.text('New'), findsNothing);
    });

    testWidgets('an upcoming event created 10 days ago does not', (tester) async {
      await _card(tester, _event(createdAgo: const Duration(days: 10), started: false));
      expect(find.text('New'), findsNothing);
    });

    testWidgets('a rated event shows its rating, past or not', (tester) async {
      await _card(tester, _event(createdAgo: const Duration(days: 30), started: true, rating: 4.3));
      expect(find.text('4.3'), findsOneWidget);
    });

    test('the event page uses the same rule', () {
      EventDetail detail({required int daysAgo, required bool started}) => EventDetail.fromJson({
        'id': 21,
        'title': 'testing 2.0',
        'mode': 'offline',
        'hasStarted': started,
        'createdAt': _now.subtract(Duration(days: daysAgo)).toUtc().toIso8601String(),
        'creator': {'id': 67},
      });
      expect(detail(daysAgo: 1, started: false).isNew, isTrue);
      expect(detail(daysAgo: 1, started: true).isNew, isFalse);
    });
  });

  group('BUG-057: "By: Name"', () {
    testWidgets('the event card', (tester) async {
      await _card(tester, _event(createdAgo: const Duration(days: 1), started: false));
      expect(find.text('By: Aathi testing'), findsOneWidget);
    });

    test('no "By :" (space before the colon) left in the app', () {
      final offenders = [
        for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
          for (final (i, l) in f.readAsLinesSync().indexed)
            if (l.contains('By :')) '${f.path}:${i + 1}',
      ];
      expect(offenders, isEmpty);
    });
  });

  test('BUG-059/060: no count shown with "Replies"/"Comments" regardless of 1', () {
    // A count interpolated straight before a plural noun ("1 Replies"). Use countLabel or a
    // 1-aware choice instead.
    final bad = RegExp(r"\$\{?[\w.!]+\}? (Replies|Comments|replies|comments)\b");
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
        for (final (i, l) in f.readAsLinesSync().indexed)
          if (bad.hasMatch(l)) '${f.path}:${i + 1}: ${l.trim()}',
    ];
    expect(offenders, isEmpty);
  });
}
