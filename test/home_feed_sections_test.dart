import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/address/data/address_models.dart';
import 'package:link_local/features/address/data/address_repository.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/business/data/business_repository.dart';
import 'package:link_local/features/home/data/doc_reminder.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';
import 'package:link_local/features/home/data/profile_congrats.dart';
import 'package:link_local/features/home/presentation/home_feed_screen.dart';
import 'package:link_local/features/members/data/members_repository.dart';
import 'package:link_local/features/notifications/data/notifications_repository.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';
import 'package:link_local/features/services/data/service_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home warms the share sheet's directory; nobody's in it here.
class _NoMembers implements MembersRepository {
  int calls = 0;
  @override
  Future<MembersPage> list({required String scope, int? areaId, String? q, int page = 1, int pageSize = 30}) async {
    calls++;
    return const MembersPage(items: [], total: 0);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

/// What `/home` returns now: workshops carry their creator and rating, providers their rating,
/// and a group's `_count.members` counts joined members only.
HomeFeed _feed({List<Map<String, dynamic>> discussions = const []}) => HomeFeed.fromJson({
      'city': {'id': 1, 'name': 'Mumbai'},
      'stats': {'members': 3, 'serviceProviders': 1, 'events': 1},
      'discussions': discussions,
      'groups': {
        'total': 1,
        'items': [
          {'id': 5, 'title': 'Runners', '_count': {'members': 12}},
        ],
      },
      'workshops': {
        'total': 1,
        'items': [
          {
            'id': 9,
            'title': 'Pottery',
            'date': '2030-11-01',
            'creator': {'id': 4, 'profile': {'name': 'Asha'}},
            'ratingAvg': 4.5,
            'ratingCount': 2,
            '_count': {'attendees': 2},
          },
        ],
      },
      'serviceProviders': {
        'total': 1,
        'items': [
          {'id': 2, 'name': 'Ravi', 'serviceTypes': [], 'ratingAvg': 4.2, 'ratingCount': 3, '_count': {'ratings': 3}},
        ],
        'services': [],
      },
    });

Future<_NoMembers> _pumpHome(WidgetTester tester, HomeFeed feed) async {
  final members = _NoMembers();
  // Wide: the test font is wider than Poppins.
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_SignedOut.new),
      homeFeedProvider.overrideWith((ref) async => feed),
      myProfileProvider.overrideWith((ref) => Completer<ProfileDetail>().future),
      myAddressProofProvider.overrideWith((ref) => Completer<AddressProofInfo>().future),
      docReminderDismissedProvider.overrideWith((ref) async => true),
      profileCongratsShownProvider.overrideWith((ref) async => true),
      customFieldsProvider.overrideWith((ref) async => const []),
      myProviderFeaturesProvider.overrideWith((ref) async => (hasMenu: false, hasDateBooking: false)),
      unreadCountProvider.overrideWith((ref) async => 0),
      membersRepositoryProvider.overrideWithValue(members),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const HomeFeedScreen()),
  ));
  await tester.pumpAndSettle();
  return members;
}

void main() {
  testWidgets('BUG-089: with no discussions the section stays, with its area picker and a note',
      (tester) async {
    await _pumpHome(tester, _feed());
    expect(find.textContaining('Community Discussions in', findRichText: true), findsOneWidget);
    expect(find.textContaining('No discussions in Mumbai yet.'), findsOneWidget);
    expect(find.text('See all discussions'), findsNothing);
  });

  testWidgets('BUG-093: the group badge is a person icon with the member count', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpHome(tester, _feed());
    final badge = find.byKey(const ValueKey('group-members-5'));
    expect(badge, findsOneWidget);
    expect(find.descendant(of: badge, matching: find.byIcon(Icons.person)), findsOneWidget);
    expect(find.descendant(of: badge, matching: find.text('12')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('12 members')), findsOneWidget, reason: 'read out as members, not a bare number');
    semantics.dispose();
  });

  testWidgets("BUG-061: Home warms the share sheet's people list", (tester) async {
    final members = await _pumpHome(tester, _feed());
    expect(members.calls, 1);
  });

  testWidgets('BUG-085: the search hint is short and says what it searches', (tester) async {
    await _pumpHome(tester, _feed());
    expect(find.widgetWithText(TextField, 'Search services, events, groups'), findsOneWidget);
  });

  testWidgets('BUG-091/092: workshop cards show the organiser and rating; providers their rating',
      (tester) async {
    await _pumpHome(tester, _feed());
    expect(find.text('By: Asha'), findsOneWidget);
    expect(find.text('By: Organizer'), findsNothing);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('4.2'), findsOneWidget);
  });
}
