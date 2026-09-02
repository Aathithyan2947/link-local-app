import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      final res = await _dio.get('/feed', queryParameters: {'areaId': areaId, 'pageSize': limit});
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

/// Which geography level the Home feed is scoped to — driven by the My Society/Lane/Area/City
/// chips, or overridden to an arbitrary area via the top location picker (see
/// widgets/area_picker_sheet.dart).
class HomeScopeState {
  const HomeScopeState({this.scope = 'city', this.overrideAreaId, this.overrideAreaLabel});
  final String scope; // society | lane | area | city
  final int? overrideAreaId;
  final String? overrideAreaLabel;
}

class HomeScopeNotifier extends Notifier<HomeScopeState> {
  @override
  HomeScopeState build() {
    ref.bindToAccount();
    return const HomeScopeState();
  }

  /// Chip tap — describes the member's OWN society/lane/area/city, so any explicit area
  /// override from the location picker is cleared.
  void setScope(String scope) => state = HomeScopeState(scope: scope);

  /// Picking an explicit area from the top location picker is equivalent to the "Area" chip,
  /// but for an arbitrary area rather than the member's own.
  void setArea(int areaId, String label) =>
      state = HomeScopeState(scope: 'area', overrideAreaId: areaId, overrideAreaLabel: label);
}

final homeScopeProvider = NotifierProvider<HomeScopeNotifier, HomeScopeState>(HomeScopeNotifier.new);

final homeFeedProvider = FutureProvider<HomeFeed>((ref) {
  ref.bindToAccount();
  final scope = ref.watch(homeScopeProvider);
  return ref.watch(homeRepositoryProvider).getHome(scope: scope.scope, areaId: scope.overrideAreaId);
});

/// An area picked independently for ONE section (Service Providers / Workshops / Groups)
/// via that section's own header dropdown — distinct from [HomeScopeState], which scopes the
/// whole feed. `null` means "use the default slice from [homeFeedProvider]".
class SectionAreaOverride {
  const SectionAreaOverride({required this.areaId, required this.label});
  final int areaId;
  final String label;
}

class SectionAreaNotifier extends Notifier<SectionAreaOverride?> {
  @override
  SectionAreaOverride? build() {
    ref.bindToAccount();
    return null;
  }
  void set(int areaId, String label) => state = SectionAreaOverride(areaId: areaId, label: label);
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
