import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/data/my_activity_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/create_group_screen.dart';
import 'package:link_local/features/discovery/presentation/my_groups_screen.dart';
import 'package:link_local/features/home/data/home_models.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

const _me = 67;

/// The member's groups on a fake server; creating one adds it to "owned".
class _Server implements DiscoveryRepository {
  final owned = <Map<String, dynamic>>[];
  int myGroupsLoads = 0;

  @override
  Future<MyGroups> myGroups() async {
    myGroupsLoads++;
    return MyGroups.fromJson({'owned': List.of(owned), 'joined': const []});
  }

  @override
  Future<List<GroupItem>> groups({String? q, bool excludeMine = false}) async => const [];

  @override
  Future<int> createGroup(Map<String, dynamic> data) async {
    owned.add({
      'id': 18,
      'title': data['title'],
      'creator': {
        'id': _me,
        'profile': {'name': 'Aathi testing'},
      },
    });
    return 18;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

void main() {
  testWidgets('a group created after My Groups was opened shows under Your Groups', (tester) async {
    tester.view.physicalSize = const Size(1170, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final server = _Server();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(Dio()),
          authControllerProvider.overrideWith(_SignedOut.new),
          discoveryRepositoryProvider.overrideWithValue(server),
          // The new group's page isn't what this test is about.
          groupDetailProvider.overrideWith((ref, id) => Completer<Never>().future),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const MyGroupsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('testing group 11'), findsNothing);
    final nav = Navigator.of(tester.element(find.byType(MyGroupsScreen)));

    // Create a group (from the + menu), land on its page, then come back to My Groups.
    nav.push(MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Group name'), 'testing group 11');
    await tester.ensureVisible(find.text('Create Group'));
    await tester.tap(find.text('Create Group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    nav.pop();
    await tester.pumpAndSettle();

    expect(server.myGroupsLoads, 2, reason: 'My Groups reloaded after the create');
    expect(find.text('testing group 11'), findsOneWidget, reason: 'listed under Your Groups, no pull-to-refresh');
    expect(find.text('Nothing here yet.'), findsWidgets); // (Groups Joined is still empty)
  });
}
