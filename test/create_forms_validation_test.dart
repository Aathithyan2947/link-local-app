import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/api_exception.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/data/event_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/create_event_screen.dart';
import 'package:link_local/features/discovery/presentation/create_group_screen.dart';
import 'package:link_local/features/feed/data/feed_repository.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/feed/presentation/create_post_screen.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

/// Records what reached the "server"; [reject] is what the server answers instead.
class _Server implements DiscoveryRepository, FeedRepository {
  final created = <Map<String, dynamic>>[];
  Object? reject;

  Future<int> _accept(Map<String, dynamic> data) async {
    created.add(data);
    if (reject != null) throw reject!;
    return 1;
  }

  @override
  Future<int> createGroup(Map<String, dynamic> data) => _accept(data);
  @override
  Future<int> createEvent(Map<String, dynamic> data) => _accept(data);
  @override
  Future<void> updateEvent(int id, Map<String, dynamic> data) => _accept(data);
  @override
  Future<PostItem> createPost({required String postType, String? text, List<String> photoUrls = const []}) async {
    await _accept({'text': text});
    return PostItem.fromJson({'id': 1, 'postType': postType});
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// A 400 the way the backend sends one: zod field errors in `details`, or a bare message.
DioException _rejected(String message, [Map<String, List<String>>? details]) {
  final req = RequestOptions(path: '/x');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: 400, data: {
      'success': false,
      'message': message,
      'details': ?details,
    }),
    type: DioExceptionType.badResponse,
  );
}

Future<_Server> _open(WidgetTester tester, Widget screen) async {
  // Wide: the test font is wider than Poppins.
  tester.view.physicalSize = const Size(1800, 5000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final server = _Server();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_SignedOut.new),
      discoveryRepositoryProvider.overrideWithValue(server),
      feedRepositoryProvider.overrideWithValue(server),
      myProfileProvider.overrideWith((ref) => Completer<ProfileDetail>().future),
    ],
    child: MaterialApp(theme: AppTheme.light, home: screen),
  ));
  await tester.pumpAndSettle();
  return server;
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _tapButton(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('BUG-071/072: Start a Group', () {
    testWidgets('name and description show their limits and stop there; # and emoji are dropped',
        (tester) async {
      await _open(tester, const CreateGroupScreen());
      expect(find.text('0/80'), findsOneWidget, reason: 'the name limit is shown by the field');
      expect(find.text('0/2000'), findsOneWidget, reason: 'and the description limit');

      await tester.enterText(_field('Group name'), 'A' * 90);
      await tester.pump();
      expect(tester.widget<TextFormField>(_field('Group name')).controller!.text, 'A' * 80);
      expect(find.text('80/80'), findsOneWidget);

      await tester.enterText(_field('Group name'), 'Book #1 Club 🏃');
      await tester.pump();
      expect(tester.widget<TextFormField>(_field('Group name')).controller!.text, 'Book 1 Club ');
    });

    testWidgets('limits show under each field and nothing is sent', (tester) async {
      final server = await _open(tester, const CreateGroupScreen());
      await tester.enterText(_field('Group name'), 'Ab');
      await tester.enterText(_field('Max members (optional)'), '1');
      await tester.tap(find.text('Paid group'));
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Create Group');

      expect(find.text('Group name must be at least 3 characters'), findsOneWidget);
      expect(find.text('Max members must be between 2 and 10,000'), findsOneWidget);
      expect(find.text('Enter a price for a paid group'), findsOneWidget);
      expect(server.created, isEmpty);

      await tester.enterText(_field('Price (₹)'), '123456789');
      await tester.pumpAndSettle();
      expect(find.text('Price can be at most ₹10,00,000'), findsOneWidget, reason: 'BUG-072: a clear limit, not a failed create');
    });

    testWidgets("the server's field message lands under that field", (tester) async {
      final server = await _open(tester, const CreateGroupScreen());
      server.reject = _rejected('Validation failed', {'title': ['Group name must include a letter']});
      await tester.enterText(_field('Group name'), 'Morning Runners');
      await _tapButton(tester, 'Create Group');

      expect(server.created, hasLength(1));
      expect(find.text('Group name must include a letter'), findsOneWidget);
      expect(find.text('Could not create group'), findsNothing);
    });

    testWidgets('a rejection without a field says what the server said', (tester) async {
      final server = await _open(tester, const CreateGroupScreen());
      server.reject = _rejected('A value you entered is too large');
      await tester.enterText(_field('Group name'), 'Morning Runners');
      await _tapButton(tester, 'Create Group');
      expect(find.text('A value you entered is too large'), findsOneWidget);
      expect(find.text('Could not create group'), findsNothing);
    });
  });

  group('BUG-073/074: Host an Event', () {
    testWidgets('date and start time are required, under their fields', (tester) async {
      final server = await _open(tester, const CreateEventScreen());
      await tester.enterText(_field('Event title'), 'Pottery for beginners');
      await _tapButton(tester, 'Create Event');
      expect(find.text('Pick a date'), findsOneWidget);
      expect(find.text('Pick a start time'), findsOneWidget);
      expect(find.text('Enter the event location'), findsOneWidget);
      expect(server.created, isEmpty);
    });

    testWidgets('duration, link, price and title limits', (tester) async {
      final server = await _open(tester, const CreateEventScreen());
      await tester.enterText(_field('Event title'), 'Ab');
      await tester.enterText(_field('Duration (minutes)'), '0');
      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Online link'), 'zoom meeting');
      await tester.tap(find.text('Paid event'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Price (₹)'), '1000001');
      await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Yoga mat'), 'x' * 101);
      await _tapButton(tester, 'Create Event');

      expect(find.text('Event title must be at least 3 characters'), findsOneWidget);
      expect(find.text('Duration must be between 15 and 1440 minutes'), findsOneWidget);
      expect(find.text('Enter a valid link starting with http:// or https://'), findsOneWidget);
      expect(find.text('Price can be at most ₹10,00,000'), findsOneWidget);
      expect(find.text('Each item can be at most 100 characters'), findsOneWidget);
      expect(server.created, isEmpty);
    });

    testWidgets("editing: the server's message for a field lands under it", (tester) async {
      final soon = DateTime.now().add(const Duration(days: 3));
      final event = EventDetail.fromJson({
        'id': 9,
        'title': 'Pottery for beginners',
        'date': '${soon.year}-${soon.month.toString().padLeft(2, '0')}-${soon.day.toString().padLeft(2, '0')}',
        'startTime': '1970-01-01T10:30:00.000Z',
        'durationMinutes': 60,
        'mode': 'offline',
        'location': 'Pai Nagar Hall',
        'isPaid': true,
        'price': '99.50',
        'maxAttendees': 30,
      });
      final server = await _open(tester, CreateEventScreen(event: event));
      expect(find.text('99.50'), findsOneWidget, reason: 'a stored ₹99.50 is no longer rounded to 100');
      server.reject = _rejected('Validation failed', {
        'maxAttendees': ["Max attendees can't be less than the 31 people already joined"],
      });
      await _tapButton(tester, 'Save Changes');

      expect(server.created, hasLength(1));
      expect(server.created.single['price'], 99.5);
      expect(find.text("Max attendees can't be less than the 31 people already joined"), findsOneWidget);
      expect(find.text('Could not save event'), findsNothing);
    });
  });

  group('BUG-070: Create Post', () {
    testWidgets('over 2000 characters is flagged under the field and not posted', (tester) async {
      final server = await _open(tester, const CreatePostScreen());
      await tester.enterText(find.byType(TextField), 'x' * 2001);
      await tester.pump();
      expect(find.text('Post can be at most 2000 characters'), findsOneWidget);
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
      expect(server.created, isEmpty);
    });

    testWidgets("the server's text message lands under the field", (tester) async {
      final server = await _open(tester, const CreatePostScreen());
      server.reject = ApiException('Post can be at most 2000 characters', statusCode: 400, details: {
        'textContent': ['Post can be at most 2000 characters'],
      });
      await tester.enterText(find.byType(TextField), 'hello neighbours');
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
      expect(server.created, hasLength(1));
      expect(find.text('Post can be at most 2000 characters'), findsOneWidget);
      expect(find.text('Could not create post'), findsNothing);
    });
  });
}
