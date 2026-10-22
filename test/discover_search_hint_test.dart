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

class _EmptyDiscovery implements DiscoveryRepository {
  @override
  Future<Section<ServiceProviderItem>> discoverServiceProviders({String scope = 'city', int? areaId}) async =>
      const Section(total: 0, items: []);
  @override
  Future<Section<WorkshopItem>> discoverEvents({String scope = 'city', int? areaId}) async =>
      const Section(total: 0, items: []);
  @override
  Future<Section<GroupItem>> discoverGroups({String scope = 'city', int? areaId}) async =>
      const Section(total: 0, items: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// BUG-090: the search box used to say just "Search" on every tab. Each tab now says what its
/// search matches.
void main() {
  testWidgets('each Discover tab says what its search covers', (tester) async {
    tester.view.physicalSize = const Size(1800, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        discoveryRepositoryProvider.overrideWithValue(_EmptyDiscovery()),
        dioProvider.overrideWithValue(Dio()),
        homeFeedProvider.overrideWith((ref) async => HomeFeed.fromJson({'city': {'id': 1, 'name': 'Mumbai'}})),
        myProfileProvider.overrideWith((ref) async => ProfileDetail.fromJson({'id': 67, 'name': 'Me'})),
      ],
      child: const MaterialApp(home: Scaffold(body: DiscoverScreen())),
    ));
    await tester.pumpAndSettle();

    Finder hint(String text) => find.widgetWithText(TextField, text);
    expect(hint('Search events, services or groups'), findsOneWidget, reason: 'All');
    expect(find.widgetWithText(TextField, 'Search'), findsNothing);

    const tabs = {
      'Events': 'Search events, venues or hosts',
      'Service Providers': 'Search providers or services',
      'Groups': 'Search groups or owners',
    };
    for (final MapEntry(key: tab, value: text) in tabs.entries) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(hint(text), findsOneWidget, reason: tab);
    }
  });
}
