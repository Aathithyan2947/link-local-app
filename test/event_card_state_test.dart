import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/discovery/presentation/widgets/discover_cards.dart';
import 'package:link_local/features/home/data/home_models.dart';

WorkshopItem _event(Map<String, dynamic> extra) =>
    WorkshopItem.fromJson({'id': 1, 'title': 'T', 'date': '2099-01-01T00:00:00.000Z', ...extra});

void main() {
  group('card action', () {
    test('open event → Join', () => expect(_event({'hasStarted': false}).action, EventAction.join));
    test('joined → Joined (even after it starts)', () {
      expect(_event({'myStatus': 'joined', 'hasStarted': false}).action, EventAction.joined);
      expect(_event({'myStatus': 'joined', 'hasStarted': true}).action, EventAction.joined);
    });
    test('awaiting approval → Pending', () {
      expect(_event({'myStatus': 'pending_approval', 'hasStarted': false}).action, EventAction.pending);
    });
    test('started, not joined → Closed', () => expect(_event({'hasStarted': true}).action, EventAction.closed));
    test('own event → Hosting, whatever else', () {
      expect(_event({'isHost': true, 'hasStarted': true}).action, EventAction.hosting);
    });
    test('the backend decides "started", not the device clock', () {
      // Far-future date, but the server says it has started.
      expect(_event({'hasStarted': true}).hasStarted, isTrue);
    });
    test('older responses fall back to the date', () {
      expect(_event({'date': '2000-01-01T00:00:00.000Z'}).hasStarted, isTrue);
      expect(_event({}).hasStarted, isFalse);
    });
  });

  Future<void> pumpBadge(WidgetTester tester, WorkshopItem e, {VoidCallback? onJoin}) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: EventActionBadge(event: e, onJoin: onJoin)))));

  testWidgets('badge labels per state', (tester) async {
    final cases = {
      'Join': _event({'hasStarted': false}),
      'Joined': _event({'myStatus': 'joined', 'hasStarted': false}),
      'Pending': _event({'myStatus': 'pending_approval', 'hasStarted': false}),
      'Closed': _event({'hasStarted': true}),
      'Hosting': _event({'isHost': true}),
    };
    for (final entry in cases.entries) {
      await pumpBadge(tester, entry.value);
      expect(find.text(entry.key), findsOneWidget, reason: entry.key);
    }
  });

  testWidgets('only Join is tappable', (tester) async {
    var taps = 0;
    await pumpBadge(tester, _event({'hasStarted': true}), onJoin: () => taps++);
    await tester.tap(find.text('Closed'));
    expect(taps, 0, reason: 'a closed event must not be joinable');

    await pumpBadge(tester, _event({'hasStarted': false}), onJoin: () => taps++);
    await tester.tap(find.text('Join'));
    expect(taps, 1);
  });

  testWidgets('after joining, the refetched card shows Joined', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ListView(children: [EventCard(event: _event({'hasStarted': false}), onJoin: () {})]))));
    expect(find.text('Join'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [EventCard(event: _event({'myStatus': 'joined', 'hasStarted': false}), onJoin: () {})]))));
    expect(find.text('Joined'), findsOneWidget);
    expect(find.text('Join'), findsNothing);
  });
}
