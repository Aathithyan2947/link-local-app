import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/data/my_activity_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/my_events_screen.dart';
import 'package:link_local/features/discovery/presentation/widgets/discover_cards.dart';
import 'package:link_local/features/home/data/home_models.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

/// An event as the backend reports it to this viewer.
Map<String, dynamic> _event(int id, String title,
        {bool started = false, bool ended = false, bool host = false, String? status}) =>
    {
      'id': id,
      'title': title,
      'date': '2030-01-0${id % 9 + 1}',
      'hasStarted': started || ended,
      'hasEnded': ended,
      'isHost': host,
      'myStatus': ?status,
    };

class _Server implements DiscoveryRepository {
  bool? askedUpcoming;

  @override
  Future<MyEvents> myEvents() async => MyEvents.fromJson({
        'hosted': [
          _event(1, 'Hosted upcoming', host: true),
          _event(2, 'Hosted ongoing', host: true, started: true),
          _event(3, 'Hosted over', host: true, ended: true),
        ],
        'attending': [
          _event(4, 'Joined upcoming', status: 'joined'),
          _event(5, 'Joined over', status: 'joined', ended: true),
        ],
      });

  @override
  Future<List<WorkshopItem>> events({String? q, bool upcoming = false}) async {
    askedUpcoming = upcoming;
    return [
      _event(6, 'Open nearby'),
      _event(7, 'Already started nearby', started: true),
      _event(1, 'Hosted upcoming', host: true),
      _event(4, 'Joined upcoming', status: 'joined'),
    ].map(WorkshopItem.fromJson).toList();
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Finder _card(String title) => find.ancestor(of: find.text(title), matching: find.byType(EventCard));

void main() {
  testWidgets('BUG-101/102: over events move to Past, marked Closed; Events near you only offers open ones',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final server = _Server();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        discoveryRepositoryProvider.overrideWithValue(server),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const MyEventsScreen()),
    ));
    await tester.pumpAndSettle();

    // Hosted: only events that aren't over; the running one says Ongoing instead of Edit.
    expect(find.text('Hosted upcoming'), findsOneWidget);
    expect(find.descendant(of: _card('Hosted upcoming'), matching: find.text('Edit')), findsOneWidget);
    expect(find.descendant(of: _card('Hosted ongoing'), matching: find.text('Ongoing')), findsOneWidget);

    // Joined: the over one is gone from here.
    expect(find.descendant(of: _card('Joined upcoming'), matching: find.byType(JoinedBadge)), findsOneWidget);

    // Past: both over events, each marked Closed.
    expect(find.text('Past Events'), findsOneWidget);
    expect(find.descendant(of: _card('Hosted over'), matching: find.text('Closed')), findsOneWidget);
    expect(find.descendant(of: _card('Joined over'), matching: find.text('Closed')), findsOneWidget);
    expect(find.text('Completed'), findsNothing, reason: 'the old label for a merely started event');

    // Events near you: open to join only — not started, not mine, not already joined.
    expect(server.askedUpcoming, isTrue, reason: 'asks for upcoming events, not oldest-first history');
    expect(find.text('Open nearby'), findsOneWidget);
    expect(find.text('Already started nearby'), findsNothing);
    expect(find.text('Hosted upcoming'), findsOneWidget, reason: 'listed under Hosted only');
    expect(find.text('Joined upcoming'), findsOneWidget, reason: 'listed under Joined only');
  });

  group('the end of an event', () {
    test('from the server when it says', () {
      expect(WorkshopItem.fromJson(_event(1, 'x', ended: true)).hasEnded, isTrue);
      expect(WorkshopItem.fromJson(_event(1, 'x', started: true)).isOngoing, isTrue);
    });

    test('otherwise start + duration, or the end of its day', () {
      final now = DateTime.now();
      String day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final started = now.subtract(const Duration(minutes: 30));
      final t = '1970-01-01T${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}:00.000';
      // Started half an hour ago: a 2-hour event is still on, a 15-minute one is over.
      expect(WorkshopItem.fromJson({'id': 1, 'date': day(started), 'startTime': t, 'durationMinutes': 120}).hasEnded,
          isFalse);
      expect(WorkshopItem.fromJson({'id': 1, 'date': day(started), 'startTime': t, 'durationMinutes': 15}).hasEnded,
          isTrue);
      // No time or duration: over once its day is.
      expect(WorkshopItem.fromJson({'id': 1, 'date': day(now)}).hasEnded, isFalse);
      expect(WorkshopItem.fromJson({'id': 1, 'date': day(now.subtract(const Duration(days: 1)))}).hasEnded, isTrue);
    });
  });
}
