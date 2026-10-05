import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/discovery/presentation/widgets/discover_cards.dart';
import 'package:link_local/features/home/data/home_models.dart';

/// The fullest card: date and time, a location line, a long organiser, and the Joined badge
/// (which carries a border the Join button doesn't).
WorkshopItem _joinedEvent() => WorkshopItem.fromJson({
  'id': 1,
  'title': 'A rather long event title that has to be cut short',
  'date': '2026-09-15T00:00:00.000Z',
  'startTime': '19:12',
  'endTime': '20:12',
  'location': 'Community Hall, Kasarvadavali, Ghodbunder Road',
  'creator': {
    'id': 9,
    'profile': {'name': 'An organiser with a long name'},
  },
  'myStatus': 'joined',
  'hasStarted': false,
  '_count': {'attendees': 3},
});

Future<void> _pumpCard(WidgetTester tester, {double textScale = 1}) async {
  tester.view.physicalSize = const Size(1170, 2532); // iPhone-width screen
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            children: [EventCard(event: _joinedEvent(), onTap: () {})],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a joined event with a location fits its card', (tester) async {
    await _pumpCard(tester);
    expect(tester.takeException(), isNull, reason: 'no "BOTTOM OVERFLOWED" in the card');
    expect(find.text('Joined'), findsOneWidget);
  });

  testWidgets('it still fits with larger system text', (tester) async {
    await _pumpCard(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card keeps its usual height when content allows', (tester) async {
    await _pumpCard(tester);
    expect(tester.getSize(find.byType(EventCard)).height, greaterThanOrEqualTo(108));
  });

  testWidgets('Joined and Join are the same height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Row(children: [JoinButton(), JoinedBadge()])),
      ),
    );
    expect(tester.getSize(find.byType(JoinedBadge)).height, tester.getSize(find.byType(JoinButton)).height);
  });
}
