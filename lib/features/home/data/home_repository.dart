import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/auth/auth_scope.dart';
import 'home_models.dart';

class HomeRepository {
  HomeRepository(this._dio);
  final Dio _dio;

  /// Community Discussions for one picked area — backs that section's own header dropdown.
  /// Reads `/feed`, which returns the same Post shape Home embeds, so [DiscussionItem]
  /// parses it unchanged.
  Future<List<DiscussionItem>> discussionsScoped(int areaId, {int limit = 3}) async {
    try {
      // The community feed's own endpoint; `/feed` never existed, so this used to 404.
      final res = await _dio.get('/posts', queryParameters: {'areaId': areaId, 'pageSize': limit});
      return ((res.data['data'] as List?) ?? [])
          .map((e) => DiscussionItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<HomeFeed> getHome({String scope = 'city', int? areaId}) async {
    try {
      final res = await _dio.get('/home', queryParameters: {
        'scope': scope,
        if (areaId != null) 'areaId': areaId,
      });
      return HomeFeed.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(ref.watch(dioProvider));
});

/// The app-wide browsing location: a geography level from the My Society/Lane/Area/City chips,
/// or an arbitrary area from a location picker (Home's top selector or the Services / Events /
/// Groups header — see widgets/area_picker_sheet.dart). Every location-based list reads this,
/// so changing it anywhere re-scopes the whole app.
class HomeScopeState {
  const HomeScopeState({this.scope = 'city', this.overrideAreaId, this.overrideAreaLabel});
  final String scope; // society | lane | area | city
  final int? overrideAreaId;
  final String? overrideAreaLabel;

  /// The whole city, with no picked area.
  bool get isWholeCity => scope == 'city' && overrideAreaId == null;

  Map<String, dynamic> toJson() => {
        'scope': scope,
        if (overrideAreaId != null) 'areaId': overrideAreaId,
        if (overrideAreaLabel != null) 'label': overrideAreaLabel,
      };

  static HomeScopeState? fromJson(Map<String, dynamic> j) {
    final scope = j['scope'];
    if (scope is! String || !const ['society', 'lane', 'area', 'city'].contains(scope)) return null;
    return HomeScopeState(
      scope: scope,
      overrideAreaId: (j['areaId'] as num?)?.toInt(),
      overrideAreaLabel: j['label'] as String?,
    );
  }
}

/// Holds [HomeScopeState] for the signed-in account and remembers it across app restarts, per
/// account. Logging out forgets it; another account starts from its own saved choice (or its
/// city), never the previous account's.
class HomeScopeNotifier extends Notifier<HomeScopeState> {
  static String _key(int userId) => 'll_location_$userId';

  int? _userId;
  /// Set once the user picks something in this session, so a slow restore can't override it.
  bool _changed = false;

  @override
  HomeScopeState build() {
    final userId = ref.watch(authScopeProvider);
    final previous = _userId;
    _userId = userId;
    _changed = false;
    if (userId == null && previous != null) _forget(previous); // logged out
    if (userId != null) _restore(userId);
    return const HomeScopeState();
  }

  /// Chip tap — describes the member's OWN society/lane/area/city, so any explicit area
  /// override from a location picker is cleared.
  void setScope(String scope) => _set(HomeScopeState(scope: scope));

  /// Picking an explicit area from a location picker is equivalent to the "Area" chip, but
  /// for an arbitrary area rather than the member's own.
  void setArea(int areaId, String label) =>
      _set(HomeScopeState(scope: 'area', overrideAreaId: areaId, overrideAreaLabel: label));

  void _set(HomeScopeState next) {
    _changed = true;
    state = next;
    final userId = _userId;
    if (userId != null) _save(userId, next);
  }

  Future<void> _restore(int userId) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key(userId));
      if (raw == null || _changed || _userId != userId) return;
      final saved = HomeScopeState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (saved != null) state = saved;
    } catch (_) {
      // Unreadable or stale storage: stay on the city.
    }
  }

  Future<void> _save(int userId, HomeScopeState s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      s.isWholeCity ? await prefs.remove(_key(userId)) : await prefs.setString(_key(userId), jsonEncode(s.toJson()));
    } catch (_) {
      // Best effort: the worst case is starting on the city next launch.
    }
  }

  Future<void> _forget(int userId) async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key(userId));
    } catch (_) {}
  }
}

final homeScopeProvider = NotifierProvider<HomeScopeNotifier, HomeScopeState>(HomeScopeNotifier.new);

/// The display name of the app-wide location — every "… in [place]" label uses this, so the
/// top selector, Home's section headers and the Services / Events / Groups tabs always agree.
/// A picked area is named at once; a chip (society / lane / area) takes the name the backend
/// actually filtered by ([HomeFeed.scopeLabel]); the whole city is the city.
String locationLabel(HomeScopeState s, HomeFeed? feed, {String fallback = 'your area'}) {
  final city = feed?.city?.name;
  if (s.isWholeCity) return city ?? fallback;
  return s.overrideAreaLabel ?? feed?.scopeLabel ?? city ?? fallback;
}

final homeFeedProvider = FutureProvider<HomeFeed>((ref) {
  ref.bindToAccount();
  final scope = ref.watch(homeScopeProvider);
  return ref.watch(homeRepositoryProvider).getHome(scope: scope.scope, areaId: scope.overrideAreaId);
});

/// An area picked independently for ONE Home section (Service Providers / Discussions /
/// Workshops / Groups) via that section's own header dropdown — distinct from
/// [HomeScopeState], the app-wide location. `null` means "follow the app-wide location".
/// Changing the app-wide location resets every section's pick, so a header never
/// contradicts the location shown at the top.
class SectionAreaOverride {
  const SectionAreaOverride({required this.areaId, required this.label});
  final int areaId;
  final String label;
}

class SectionAreaNotifier extends Notifier<SectionAreaOverride?> {
  @override
  SectionAreaOverride? build() {
    ref.bindToAccount();
    ref.watch(homeScopeProvider); // a new app-wide location clears this section's pick
    return null;
  }
  void set(int areaId, String label) => state = SectionAreaOverride(areaId: areaId, label: label);

  /// Back to the section's default, city-wide slice.
  void clear() => state = null;
}

final spSectionAreaProvider = NotifierProvider<SectionAreaNotifier, SectionAreaOverride?>(SectionAreaNotifier.new);
final discussionsSectionAreaProvider =
    NotifierProvider<SectionAreaNotifier, SectionAreaOverride?>(SectionAreaNotifier.new);

/// Discussions for a single picked area, keyed by areaId — the discussions counterpart to
/// `spSectionScopedProvider` and friends in discovery_repository.dart.
final discussionsSectionScopedProvider = FutureProvider.family<List<DiscussionItem>, int>((ref, areaId) {
  ref.bindToAccount();
  return ref.watch(homeRepositoryProvider).discussionsScoped(areaId);
});
final workshopsSectionAreaProvider =
    NotifierProvider<SectionAreaNotifier, SectionAreaOverride?>(SectionAreaNotifier.new);
final groupsSectionAreaProvider =
    NotifierProvider<SectionAreaNotifier, SectionAreaOverride?>(SectionAreaNotifier.new);
