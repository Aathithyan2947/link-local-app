import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/discover_screen.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';
import 'package:link_local/features/services/data/service_profile_repository.dart';

class _FakeDiscovery implements DiscoveryRepository {
  final spCalls = <int?>[];

  @override
  Future<Section<ServiceProviderItem>> discoverServiceProviders({String scope = 'city', int? areaId}) async {
    spCalls.add(areaId);
    final items = [
      ServiceProviderItem.fromJson({'id': 1, 'name': areaId == null ? 'City SP' : 'Area SP', 'serviceTypes': []}),
    ];
    return Section(total: areaId == null ? 28 : 5, items: items);
  }

  @override
  Future<Section<WorkshopItem>> discoverEvents({String scope = 'city', int? areaId}) async =>
      const Section(total: 0, items: []);
  @override
  Future<Section<GroupItem>> discoverGroups({String scope = 'city', int? areaId}) async =>
      const Section(total: 0, items: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _FakeAreas implements ServiceProfileRepository {
  @override
  Future<List<SelectedArea>> searchAreas({String? q, int? cityId}) async =>
      const [SelectedArea(id: 7, areaName: 'Pai Nagar')];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  testWidgets('the header arrow picks an area, and "All of" returns to the city', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = _FakeDiscovery();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        discoveryRepositoryProvider.overrideWithValue(repo),
        serviceProfileRepositoryProvider.overrideWithValue(_FakeAreas()),
        dioProvider.overrideWithValue(Dio()),
        homeFeedProvider.overrideWith((ref) async => HomeFeed.fromJson({'city': {'id': 1, 'name': 'Mumbai'}})),
        myProfileProvider.overrideWith((ref) async => ProfileDetail.fromJson({'id': 67, 'name': 'Me'})),
      ],
      child: const MaterialApp(home: Scaffold(body: DiscoverScreen())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Service Providers').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Mumbai(28)', findRichText: true), findsWidgets,
        reason: 'count is the real total, not the 1 row loaded');

    await tester.tap(find.textContaining('Service Providers in', findRichText: true).first);
    await tester.pumpAndSettle();
    expect(find.text('All of Mumbai'), findsOneWidget, reason: 'the arrow opens the area sheet');
    await tester.tap(find.text('Pai Nagar'));
    await tester.pumpAndSettle();
    expect(repo.spCalls.last, 7);
    // It's the app-wide location: Home and every other tab now follow it too.
    final container = ProviderScope.containerOf(tester.element(find.byType(DiscoverScreen)));
    expect(container.read(homeScopeProvider).overrideAreaId, 7);
    expect(find.textContaining('Pai Nagar(5)', findRichText: true), findsWidgets);
    expect(find.text('Area SP'), findsOneWidget);

    await tester.tap(find.textContaining('Service Providers in', findRichText: true).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All of Mumbai'));
    await tester.pumpAndSettle();
    expect(repo.spCalls.last, isNull);
    expect(find.text('City SP'), findsOneWidget);
  });
}
