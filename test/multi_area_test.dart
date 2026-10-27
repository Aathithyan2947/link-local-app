import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/home/data/doc_reminder.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';
import 'package:link_local/features/home/data/profile_congrats.dart';
import 'package:link_local/features/home/presentation/home_feed_screen.dart';
import 'package:link_local/features/home/presentation/widgets/area_picker_sheet.dart';
import 'package:link_local/features/members/data/members_repository.dart';
import 'package:link_local/features/notifications/data/notifications_repository.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';
import 'package:link_local/features/services/data/service_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _paiNagar = SelectedArea(id: 1, areaName: 'Pai Nagar');
const _gaimukh = SelectedArea(id: 2, areaName: 'Gaimukh');
const _kasar = SelectedArea(id: 3, areaName: 'Kasarvadavali');

/// The areas of Mumbai, searchable by name.
class _Areas implements ServiceProfileRepository {
  _Areas([this.all = const [_paiNagar, _gaimukh, _kasar]]);
  final List<SelectedArea> all;

  @override
  Future<List<SelectedArea>> searchAreas({String? q, int? cityId}) async =>
      all.where((a) => a.areaName.toLowerCase().contains((q ?? '').toLowerCase())).toList();

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// Records which areas Home's sections asked for.
class _Discovery implements DiscoveryRepository {
  final spRequests = <List<int>>[];

  @override
  Future<Section<ServiceProviderItem>> serviceProvidersScoped(List<int> areaIds, {int pageSize = 8}) async {
    spRequests.add(areaIds);
    return Section(total: 2, items: [
      ServiceProviderItem.fromJson({'id': 4, 'name': 'Meera', 'serviceTypes': [], '_count': {'ratings': 0}}),
      ServiceProviderItem.fromJson({'id': 5, 'name': 'Kiran', 'serviceTypes': [], '_count': {'ratings': 0}}),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

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

/// Opens the picker from a button and records what it returned.
Future<List<List<SelectedArea>?>> _openSheet(WidgetTester tester, {_Areas? areas, List<SelectedArea> initial = const []}) async {
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final results = <List<SelectedArea>?>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [serviceProfileRepositoryProvider.overrideWithValue(areas ?? _Areas())],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                results.add(await showAreaMultiSheet(context, cityId: 1, cityName: 'Mumbai', initial: initial)),
            child: const Text('pick'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('pick'));
  await tester.pumpAndSettle();
  return results;
}

bool _ticked(WidgetTester tester, String title) =>
    tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, title)).value == true;

/// A Dio that answers every request with an empty page and remembers what was asked.
Dio _recordingDio(List<RequestOptions> requests) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.httpClientAdapter = _Adapter(requests);
  return dio;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.requests);
  final List<RequestOptions> requests;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode({'data': [], 'meta': {'total': 0}}), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('BUG-086: picking several areas', () {
    testWidgets('tick any number; the button says how many; they come back in the order ticked', (tester) async {
      final results = await _openSheet(tester);
      expect(_ticked(tester, 'All of Mumbai'), isTrue, reason: 'nothing picked yet is the whole city');
      expect(find.text('Show all of Mumbai'), findsOneWidget);

      await tester.tap(find.text('Gaimukh'));
      await tester.pump();
      await tester.tap(find.text('Pai Nagar'));
      await tester.pump();
      expect(_ticked(tester, 'All of Mumbai'), isFalse);
      expect(find.text('Show 2 areas'), findsOneWidget);

      await tester.tap(find.text('Show 2 areas'));
      await tester.pumpAndSettle();
      expect(results.single!.map((a) => a.areaName), ['Gaimukh', 'Pai Nagar']);
    });

    testWidgets('ticked areas stay listed while searching; "All of" clears them', (tester) async {
      final results = await _openSheet(tester, initial: const [_kasar]);
      expect(_ticked(tester, 'Kasarvadavali'), isTrue, reason: "the section's current pick");

      await tester.enterText(find.byType(TextField), 'pai');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Kasarvadavali'), findsOneWidget, reason: 'still shown as picked');

      await tester.tap(find.text('All of Mumbai'));
      await tester.pump();
      expect(find.byType(InputChip), findsNothing);
      await tester.tap(find.text('Show all of Mumbai'));
      await tester.pumpAndSettle();
      expect(results.single, isEmpty, reason: 'empty means the whole city');
    });

    testWidgets('closing the sheet changes nothing', (tester) async {
      final results = await _openSheet(tester);
      await tester.tap(find.text('Pai Nagar'));
      await tester.pump();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });

    testWidgets('at most 20 areas', (tester) async {
      final many = _Areas([for (var i = 1; i <= 21; i++) SelectedArea(id: i, areaName: 'Area $i')]);
      await _openSheet(tester, areas: many, initial: [for (var i = 1; i <= 20; i++) SelectedArea(id: i, areaName: 'Area $i')]);
      expect(find.text('You can pick up to 20 areas'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Area 21');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final last = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Area 21'));
      expect(last.onChanged, isNull, reason: 'a 21st can not be ticked');
    });

    test('a section names its areas briefly, and is keyed the same whatever the order', () {
      expect(SectionAreas([_paiNagar]).label, 'Pai Nagar');
      expect(SectionAreas([_paiNagar, _gaimukh]).label, 'Pai Nagar, Gaimukh');
      expect(SectionAreas([_kasar, _paiNagar, _gaimukh]).label, 'Kasarvadavali +2');
      expect(SectionAreas([_kasar, _paiNagar]).key, SectionAreas([_paiNagar, _kasar]).key);
      expect(areaIdsOf('1,3'), [1, 3]);
    });

    test('the lists ask the server for all the picked areas at once', () async {
      final requests = <RequestOptions>[];
      final dio = _recordingDio(requests);
      await DiscoveryRepository(dio).serviceProvidersScoped([1, 3]);
      await DiscoveryRepository(dio).eventsScoped([1, 3]);
      await DiscoveryRepository(dio).groupsScoped([1, 3]);
      await HomeRepository(dio).discussionsScoped([1, 3]);
      expect(requests.map((r) => r.path), ['/service-providers', '/events', '/groups', '/posts']);
      for (final r in requests) {
        expect(r.queryParameters['areaIds'], '1,3');
      }
    });

    testWidgets("Home's Service provider section shows the picked areas", (tester) async {
      tester.view.physicalSize = const Size(1800, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final discovery = _Discovery();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(Dio()),
          authControllerProvider.overrideWith(_SignedOut.new),
          homeFeedProvider.overrideWith((ref) async => HomeFeed.fromJson({
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
                  'services': const [],
                },
              })),
          discoveryRepositoryProvider.overrideWithValue(discovery),
          serviceProfileRepositoryProvider.overrideWithValue(_Areas()),
          myProfileProvider.overrideWith((ref) => Completer<ProfileDetail>().future),
          myAddressProofProvider.overrideWith((ref) => Completer<AddressProofInfo>().future),
          docReminderDismissedProvider.overrideWith((ref) async => true),
          profileCongratsShownProvider.overrideWith((ref) async => true),
          customFieldsProvider.overrideWith((ref) async => const []),
          myProviderFeaturesProvider.overrideWith((ref) async => (hasMenu: false, hasDateBooking: false)),
          unreadCountProvider.overrideWith((ref) async => 0),
          membersRepositoryProvider.overrideWithValue(_NoMembers()),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeFeedScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mumbai(1)', findRichText: true), findsWidgets);

      await tester.tap(find.textContaining('Service provider in', findRichText: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pai Nagar'));
      await tester.tap(find.text('Gaimukh'));
      await tester.pump();
      await tester.tap(find.text('Show 2 areas'));
      await tester.pumpAndSettle();

      expect(discovery.spRequests, [
        [1, 2],
      ]);
      expect(find.textContaining('Pai Nagar, Gaimukh(2)', findRichText: true), findsOneWidget);
      expect(find.text('Meera'), findsOneWidget);
      expect(find.text('Ravi'), findsNothing, reason: 'only providers from the picked areas');
    });
  });
}
