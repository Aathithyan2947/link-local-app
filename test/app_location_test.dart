import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/auth/auth_scope.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/feed/data/feed_repository.dart';
import 'package:link_local/features/feed/data/post_models.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the location each Discover list was asked for.
class _FakeDiscovery implements DiscoveryRepository {
  final calls = <String, (String, int?)>{};

  @override
  Future<Section<ServiceProviderItem>> discoverServiceProviders({String scope = 'city', int? areaId}) async {
    calls['sps'] = (scope, areaId);
    return const Section(total: 0, items: []);
  }

  @override
  Future<Section<WorkshopItem>> discoverEvents({String scope = 'city', int? areaId}) async {
    calls['events'] = (scope, areaId);
    return const Section(total: 0, items: []);
  }

  @override
  Future<Section<GroupItem>> discoverGroups({String scope = 'city', int? areaId}) async {
    calls['groups'] = (scope, areaId);
    return const Section(total: 0, items: []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _FakeFeed implements FeedRepository {
  (String?, int?)? lastPosts;

  @override
  Future<List<PostItem>> posts({String? postType, String? scope, int? areaId}) async {
    lastPosts = (scope, areaId);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

const _key = 'll_location_5';

ProviderContainer _container({_FakeDiscovery? discovery, _FakeFeed? feed}) {
  final c = ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      discoveryRepositoryProvider.overrideWithValue(discovery ?? _FakeDiscovery()),
      feedRepositoryProvider.overrideWithValue(feed ?? _FakeFeed()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Lets SharedPreferences reads/writes (async, fire-and-forget) settle.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a location picked once scopes Services, Events, Groups and the community feed', () async {
    final discovery = _FakeDiscovery();
    final feed = _FakeFeed();
    final c = _container(discovery: discovery, feed: feed);
    c.read(authScopeProvider.notifier).setUserId(5);

    c.read(homeScopeProvider.notifier).setArea(7, 'Koliwada');
    await Future.wait([
      c.read(discoverServiceProvidersProvider.future),
      c.read(discoverEventsProvider.future),
      c.read(discoverGroupsProvider.future),
      c.read(feedProvider.future),
    ]);
    expect(discovery.calls['sps'], ('area', 7));
    expect(discovery.calls['events'], ('area', 7));
    expect(discovery.calls['groups'], ('area', 7));
    expect(feed.lastPosts, ('area', 7));

    // A chip (here My Society) applies everywhere too.
    c.read(homeScopeProvider.notifier).setScope('society');
    await c.read(discoverGroupsProvider.future);
    expect(discovery.calls['groups'], ('society', null));
  });

  test("changing the location resets Home's per-section picks", () async {
    final c = _container();
    c.read(authScopeProvider.notifier).setUserId(5);
    c.read(spSectionAreaProvider.notifier).set(8, 'Gaimukh');
    c.read(groupsSectionAreaProvider.notifier).set(8, 'Gaimukh');
    expect(c.read(spSectionAreaProvider)?.label, 'Gaimukh');

    c.read(homeScopeProvider.notifier).setArea(7, 'Koliwada');
    expect(c.read(spSectionAreaProvider), isNull);
    expect(c.read(groupsSectionAreaProvider), isNull);
  });

  test('the location is remembered per account across restarts', () async {
    final first = _container();
    first.read(authScopeProvider.notifier).setUserId(5);
    first.read(homeScopeProvider);
    first.read(homeScopeProvider.notifier).setArea(7, 'Koliwada');
    await _settle();
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(_key)!), {'scope': 'area', 'areaId': 7, 'label': 'Koliwada'});

    // "Restart": a fresh container for the same account restores it.
    final second = _container();
    second.read(authScopeProvider.notifier).setUserId(5);
    second.read(homeScopeProvider);
    await _settle();
    expect(second.read(homeScopeProvider).overrideAreaId, 7);
    expect(second.read(homeScopeProvider).overrideAreaLabel, 'Koliwada');
  });

  test("another account doesn't inherit it, and logging out forgets it", () async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode({'scope': 'area', 'areaId': 7, 'label': 'Koliwada'}),
    });
    final c = _container();
    c.read(authScopeProvider.notifier).setUserId(5);
    c.read(homeScopeProvider);
    await _settle();
    expect(c.read(homeScopeProvider).overrideAreaId, 7);

    c.read(authScopeProvider.notifier).setUserId(6); // switch account
    c.read(homeScopeProvider);
    await _settle();
    expect(c.read(homeScopeProvider).isWholeCity, isTrue);

    c.read(authScopeProvider.notifier).setUserId(5);
    c.read(homeScopeProvider);
    await _settle();
    c.read(authScopeProvider.notifier).setUserId(null); // log out
    c.read(homeScopeProvider);
    await _settle();
    expect((await SharedPreferences.getInstance()).getString(_key), isNull);
  });

  test('choosing the whole city again clears the saved choice', () async {
    final c = _container();
    c.read(authScopeProvider.notifier).setUserId(5);
    c.read(homeScopeProvider);
    c.read(homeScopeProvider.notifier).setArea(7, 'Koliwada');
    await _settle();
    c.read(homeScopeProvider.notifier).setScope('city');
    await _settle();
    expect((await SharedPreferences.getInstance()).getString(_key), isNull);
  });

  group('locationLabel', () {
    final feed = HomeFeed.fromJson({
      'city': {'name': 'Vasai-Virar', 'state': 'Maharashtra'},
      'scopeLabel': 'Sai Nagar',
    });
    test('whole city → the city', () => expect(locationLabel(const HomeScopeState(), feed), 'Vasai-Virar'));
    test('a picked area → that area, even before the feed reloads', () {
      expect(
        locationLabel(const HomeScopeState(scope: 'area', overrideAreaId: 7, overrideAreaLabel: 'Koliwada'), feed),
        'Koliwada',
      );
    });
    test('a chip → the place the backend filtered by', () {
      expect(locationLabel(const HomeScopeState(scope: 'society'), feed), 'Sai Nagar');
    });
    test('nothing loaded yet → the fallback', () {
      expect(locationLabel(const HomeScopeState(scope: 'lane'), null, fallback: 'here'), 'here');
    });
  });

  test("Home's section headers name the current location, not a hard-coded city", () {
    final source = File('lib/features/home/presentation/home_feed_screen.dart').readAsStringSync();
    expect(
      RegExp(r'Override\?\.label \?\? feed\.city').hasMatch(source),
      isFalse,
      reason: 'a section header fell back to the city instead of the app-wide location',
    );
    expect(source.contains('locationLabel(scopeState, feed)'), isTrue);
  });
}
