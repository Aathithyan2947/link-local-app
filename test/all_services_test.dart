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
import 'package:link_local/features/discovery/data/service_catalog_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/all_services_screen.dart';
import 'package:link_local/features/discovery/presentation/discover_screen.dart';
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

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

class _NoMembers implements MembersRepository {
  @override
  Future<MembersPage> list({required String scope, int? areaId, String? q, int page = 1, int pageSize = 30}) async =>
      const MembersPage(items: [], total: 0);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// `/service-providers/services` for Mumbai.
final _catalog = [
  for (final c in [
    {
      'id': 1,
      'name': 'Beauticians',
      'services': [
        {'id': 21, 'name': 'Hair stylist', 'count': 3},
        {'id': 22, 'name': 'Mehendi artist', 'count': 0},
      ],
    },
    {
      'id': 2,
      'name': 'Tutors',
      'services': [
        {'id': 31, 'name': 'Maths tutor', 'count': 1},
      ],
    },
  ])
    ServiceCatalogCategory.fromJson(c),
];

final _feed = HomeFeed.fromJson({
  'city': {'id': 1, 'name': 'Mumbai'},
  'stats': {'members': 3, 'serviceProviders': 1, 'events': 0},
  'discussions': const [],
  'groups': {'total': 0, 'items': const []},
  'workshops': {'total': 0, 'items': const []},
  'serviceProviders': {
    'total': 1,
    'items': [
      {'id': 2, 'name': 'Ravi', 'serviceTypes': [], '_count': {'ratings': 0}},
    ],
    'services': [
      {'name': 'Hair stylist', 'count': 3},
    ],
  },
});

/// What the filtered list asked for: (service id, picked area id).
final _providerRequests = <(int, int?)>[];

Future<void> _pump(WidgetTester tester, Widget home) async {
  _providerRequests.clear();
  // Wide: the test font is wider than Poppins.
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_SignedOut.new),
      homeFeedProvider.overrideWith((ref) async => _feed),
      serviceCatalogProvider.overrideWith((ref) async => _catalog),
      providersForServiceProvider.overrideWith((ref, id) async {
        _providerRequests.add((id, ref.watch(homeScopeProvider).overrideAreaId));
        return Section(
            total: id == 21 ? 1 : 0,
            items: [
              if (id == 21)
                ServiceProviderItem.fromJson({
                  'id': 2,
                  'name': 'Ravi Kumar',
                  'serviceTypes': [
                    {'subcategory': {'name': 'Hair stylist'}},
                  ],
                  '_count': {'ratings': 0},
                }),
            ],
          );
      }),
      myProfileProvider.overrideWith((ref) => Completer<ProfileDetail>().future),
      myAddressProofProvider.overrideWith((ref) => Completer<AddressProofInfo>().future),
      docReminderDismissedProvider.overrideWith((ref) async => true),
      profileCongratsShownProvider.overrideWith((ref) async => true),
      customFieldsProvider.overrideWith((ref) async => const []),
      myProviderFeaturesProvider.overrideWith((ref) async => (hasMenu: false, hasDateBooking: false)),
      unreadCountProvider.overrideWith((ref) async => 0),
      membersRepositoryProvider.overrideWithValue(_NoMembers()),
    ],
    child: MaterialApp(theme: AppTheme.light, home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('BUG-087: All Services', () {
    testWidgets("Home's Explore More opens it", (tester) async {
      await _pump(tester, const HomeFeedScreen());
      await tester.ensureVisible(find.text('Explore\nMore...'));
      await tester.tap(find.text('Explore\nMore...'));
      await tester.pumpAndSettle();
      expect(find.byType(AllServicesScreen), findsOneWidget);
    });

    testWidgets('every service is a tile under its category, with its provider count', (tester) async {
      await _pump(tester, const AllServicesScreen());
      expect(find.text('in Mumbai'), findsOneWidget);
      expect(find.text('BEAUTICIANS'), findsOneWidget);
      expect(find.text('TUTORS'), findsOneWidget);
      expect(find.text('Hair stylist'), findsOneWidget);
      expect(find.text('3 providers'), findsOneWidget);
      expect(find.text('1 provider'), findsOneWidget);
      expect(find.text('None yet'), findsOneWidget, reason: 'a service nobody offers yet still has its tile');
    });

    testWidgets('search narrows the tiles by service or category', (tester) async {
      await _pump(tester, const AllServicesScreen());
      await tester.enterText(find.byType(TextField), 'mehe');
      await tester.pump();
      expect(find.text('Mehendi artist'), findsOneWidget);
      expect(find.text('Hair stylist'), findsNothing);
      expect(find.text('TUTORS'), findsNothing);

      await tester.enterText(find.byType(TextField), 'tutors');
      await tester.pump();
      expect(find.text('Maths tutor'), findsOneWidget);
      expect(find.text('Hair stylist'), findsNothing);
    });

    testWidgets("a tile opens the Service Providers list limited to that service", (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, const AllServicesScreen());
      await tester.tap(find.text('Hair stylist'));
      await tester.pumpAndSettle();

      expect(find.byType(DiscoverScreen), findsOneWidget);
      expect(find.text('Local Service Providers nearby'), findsOneWidget, reason: 'the Services tab screen itself');
      expect(find.bySemanticsLabel('Showing Hair stylist only'), findsOneWidget);
      expect(find.textContaining('Hair stylist in', findRichText: true), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(_providerRequests.last.$1, 21, reason: 'filtered by the server, not from a page of 50');
      expect(find.text('Events'), findsNothing, reason: 'only this service: no tabs to wander off to');
      expect(find.byIcon(Icons.close), findsNothing, reason: 'the filter is not cleared here');
      semantics.dispose();
    });

    testWidgets('the filter stays when the area changes; back returns to All Services', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, const AllServicesScreen());
      await tester.tap(find.text('Hair stylist'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(DiscoverScreen)));

      container.read(homeScopeProvider.notifier).setArea(7, 'Pai Nagar');
      await tester.pumpAndSettle();
      expect(_providerRequests.last, (21, 7));
      expect(find.bySemanticsLabel('Showing Hair stylist only'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.byType(DiscoverScreen), findsNothing);
      expect(find.text('All Services'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets("its search stays its own; the Services tab's is untouched", (tester) async {
      await _pump(tester, const AllServicesScreen());
      await tester.tap(find.text('Hair stylist'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(DiscoverScreen)));

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No Hair stylist providers found'), findsOneWidget);
      expect(container.read(discoverQueryProvider), '');
      expect(container.read(discoverTabProvider), 0);
    });

    testWidgets('a service nobody offers yet says so', (tester) async {
      await _pump(tester, const AllServicesScreen());
      await tester.tap(find.text('Mehendi artist'));
      await tester.pumpAndSettle();
      expect(find.text('No Mehendi artist providers found'), findsOneWidget);
    });
  });
}
