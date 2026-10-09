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
import 'package:link_local/features/discovery/presentation/my_groups_screen.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/payments/presentation/payment_method_screen.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

const _me = 60;

Map<String, dynamic> _g(int id, String title, {int creator = 7, bool paid = false, bool approval = false}) => {
  'id': id,
  'title': title,
  'isPaid': paid,
  'price': paid ? 199 : null,
  'adminApprovalNeeded': approval,
  'creator': {
    'id': creator,
    'profile': {'name': creator == _me ? 'Me' : 'simran 5'},
  },
  '_count': {'members': 3},
};

/// A small group server that answers like the backend: "Groups Joined" leaves out the member's
/// own groups, and "Groups near you" (excludeMine) leaves out own, joined and pending ones.
class _Server implements DiscoveryRepository {
  _Server(this.all);
  final List<Map<String, dynamic>> all;
  final status = <int, String>{}; // my membership per group
  final joinCalls = <int>[];
  final nearbyRequests = <bool>[];
  Completer<void>? gate;
  String? refuse; // the server's 400 message, e.g. "This group is full"

  @override
  Future<MyGroups> myGroups() async => MyGroups.fromJson({
    'owned': all.where((g) => g['creator']['id'] == _me).toList(),
    'joined': all.where((g) => g['creator']['id'] != _me && status[g['id']] == 'joined').toList(),
  });

  @override
  Future<List<GroupItem>> groups({String? q, bool excludeMine = false}) async {
    nearbyRequests.add(excludeMine);
    return all
        .where((g) => !excludeMine || (g['creator']['id'] != _me && status[g['id']] == null))
        .map(GroupItem.fromJson)
        .toList();
  }

  @override
  Future<String?> joinGroup(int id) async {
    joinCalls.add(id);
    if (gate != null) await gate!.future;
    final g = all.firstWhere((g) => g['id'] == id);
    final req = RequestOptions(path: '/groups/$id/join');
    if (refuse != null) {
      throw DioException(
        requestOptions: req,
        response: Response(requestOptions: req, statusCode: 400, data: {'success': false, 'message': refuse}),
        type: DioExceptionType.badResponse,
      );
    }
    if (g['isPaid'] == true) {
      throw DioException(
        requestOptions: req,
        response: Response(requestOptions: req, statusCode: 402, data: {'success': false, 'message': 'Payment required'}),
        type: DioExceptionType.badResponse,
      );
    }
    return status[id] = g['adminApprovalNeeded'] == true ? 'pending_approval' : 'joined';
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<void> _open(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1170, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        discoveryRepositoryProvider.overrideWithValue(server),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const MyGroupsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The section a group's card is shown under.
String? _sectionOf(WidgetTester tester, String title) {
  final cards = find.text(title);
  if (cards.evaluate().isEmpty) return null;
  final y = tester.getTopLeft(cards.first).dy;
  String? section;
  for (final s in ['Your Groups', 'Groups Joined', 'Groups near you']) {
    if (tester.getTopLeft(find.text(s)).dy < y) section = s;
  }
  return section;
}

Finder _joinOn(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
  matching: find.text('Join'),
);

void main() {
  testWidgets('BUG-047: my own group shows only under Your Groups', (tester) async {
    final s = _Server([_g(1, 'my own group', creator: _me), _g(2, 'test group 1')])..status[1] = 'joined';
    await _open(tester, s);

    expect(find.text('my own group'), findsOneWidget, reason: 'listed once');
    expect(_sectionOf(tester, 'my own group'), 'Your Groups');
    expect(_sectionOf(tester, 'test group 1'), 'Groups near you');
    expect(s.nearbyRequests, everyElement(isTrue), reason: '"Groups near you" asks for groups that are not mine');
  });

  testWidgets('BUG-046: Join says so and the group moves to Groups Joined', (tester) async {
    final s = _Server([_g(2, 'test group 1'), _g(3, 'hair salon')]);
    await _open(tester, s);
    expect(_sectionOf(tester, 'test group 1'), 'Groups near you');

    await tester.tap(_joinOn('test group 1'));
    await tester.pumpAndSettle();

    expect(find.text('You joined test group 1'), findsOneWidget);
    expect(find.text('test group 1'), findsOneWidget);
    expect(_sectionOf(tester, 'test group 1'), 'Groups Joined');
    expect(_sectionOf(tester, 'hair salon'), 'Groups near you');
  });

  testWidgets('while joining the button spins and a second tap sends nothing', (tester) async {
    final s = _Server([_g(2, 'test group 1')])..gate = Completer<void>();
    await _open(tester, s);
    await tester.tap(_joinOn('test group 1'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_joinOn('test group 1'), findsNothing);
    s.gate!.complete();
    await tester.pumpAndSettle();
    expect(s.joinCalls, [2]);
  });

  testWidgets('a group that needs approval: request message, and it leaves the list', (tester) async {
    final s = _Server([_g(4, 'Book Readers', approval: true)]);
    await _open(tester, s);
    await tester.tap(_joinOn('Book Readers'));
    await tester.pumpAndSettle();
    expect(find.text('Request sent. The admin will approve you.'), findsOneWidget);
    expect(find.text('Book Readers'), findsNothing, reason: 'not joined yet, and not offered again');
  });

  testWidgets('a paid group opens payment instead of failing', (tester) async {
    final s = _Server([_g(5, 'Yoga Club', paid: true)]);
    await _open(tester, s);
    await tester.tap(_joinOn('Yoga Club'));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentMethodScreen), findsOneWidget);
    expect(s.joinCalls, isEmpty, reason: 'Join alone never admits to a paid group');
    expect(find.text('Could not join Yoga Club'), findsNothing);
  });

  testWidgets("a refusal shows the server's reason, and the group stays", (tester) async {
    final s = _Server([_g(6, 'Morning Walkers')])..refuse = 'This group is full';
    await _open(tester, s);
    await tester.tap(_joinOn('Morning Walkers'));
    await tester.pumpAndSettle();
    expect(find.text('This group is full'), findsOneWidget);
    expect(_sectionOf(tester, 'Morning Walkers'), 'Groups near you');
    expect(_joinOn('Morning Walkers'), findsOneWidget);
  });
}
