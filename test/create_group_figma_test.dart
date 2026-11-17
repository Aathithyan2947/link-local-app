import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/api_exception.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/data/group_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/create_event_screen.dart';
import 'package:link_local/features/discovery/presentation/create_group_screen.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

/// Records what reached the "server", then refuses, so a create doesn't navigate away.
class _Server implements DiscoveryRepository {
  final sent = <Map<String, dynamic>>[];

  Future<int> _record(Map<String, dynamic> data) async {
    sent.add(data);
    throw ApiException('stop', statusCode: 400);
  }

  @override
  Future<int> createGroup(Map<String, dynamic> data) => _record(data);
  @override
  Future<void> updateGroup(int id, Map<String, dynamic> data) => _record(data);
  @override
  Future<int> createEvent(Map<String, dynamic> data) => _record(data);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<_Server> _open(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1800, 5000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final server = _Server();
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_SignedOut.new),
      discoveryRepositoryProvider.overrideWithValue(server),
      myProfileProvider.overrideWith((ref) async => ProfileDetail.fromJson({
            'id': 1,
            'name': 'Asha',
            'address': {
              'apartment': 'Shree Ganesh Apartments',
              'lane1': 'Lane 2',
              'area': {
                'areaName': 'South Delhi',
                'city': {'id': 4, 'name': 'Delhi'},
              },
            },
          })),
    ],
    child: MaterialApp(theme: AppTheme.light, home: screen),
  ));
  await tester.pumpAndSettle();
  return server;
}

Future<void> _pick(WidgetTester tester, String option) async {
  await tester.tap(find.byKey(const ValueKey('audience-picker')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option));
  await tester.pumpAndSettle();
}

void main() {
  group('BUG-080: Create Group follows the Figma', () {
    testWidgets('"Members from", the heading, the round photo and the Figma\'s toggles', (tester) async {
      await _open(tester, const CreateGroupScreen());
      expect(find.text('Members from: '), findsOneWidget);
      expect(find.text('South Delhi'), findsOneWidget, reason: 'the member\'s area by default');
      expect(find.text('Create Group'), findsNWidgets(2), reason: 'the heading and the button');
      expect(find.bySemanticsLabel('Add a group photo'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget, reason: 'the photo button is round');
      for (final t in ['Private Group', 'Only invited people can find this group', 'Approve Members',
          'You review each join request', 'Paid Group']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.byType(AppBar), findsNothing, reason: 'the Figma has no app bar, just the picker row');
    });

    testWidgets('sends the area by default, or what was picked (BUG-115)', (tester) async {
      final server = await _open(tester, const CreateGroupScreen());
      await tester.enterText(find.widgetWithText(TextFormField, 'Group name'), 'Morning Walkers');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Group'));
      await tester.pumpAndSettle();
      expect(server.sent.last['audience'], 'area');

      await _pick(tester, 'My Society');
      expect(find.text('Shree Ganesh Apartments'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Group'));
      await tester.pumpAndSettle();
      expect(server.sent.last['audience'], 'society');
    });

    testWidgets('editing starts from the group\'s own audience', (tester) async {
      final server = await _open(
        tester,
        CreateGroupScreen(
          group: GroupDetail.fromJson({
            'id': 3,
            'title': 'Lane Cyclists',
            'audience': 'lane',
            'creator': {
              'profile': {'name': 'Asha'},
            },
            '_count': {'members': 2},
          }),
        ),
      );
      expect(find.text('Lane 2'), findsOneWidget, reason: 'Members from: Lane 2');
      expect(find.text('Edit Group'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
      await tester.pumpAndSettle();
      expect(server.sent.single['audience'], 'lane');
    });
  });

  group('BUG-115: Host an Event has the same picker', () {
    testWidgets('"Post in" defaults to the area and sends the pick', (tester) async {
      await _open(tester, const CreateEventScreen());
      expect(find.text('Post in: '), findsOneWidget);
      expect(find.text('South Delhi'), findsOneWidget);
      await _pick(tester, 'My City');
      expect(find.text('Delhi'), findsOneWidget);
    });
  });
}
