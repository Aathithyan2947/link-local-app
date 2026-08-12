import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/auth/auth_scope.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';

/// Serves a different profile per account, and records who was asked.
class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this._whoAmI);
  final int? Function() _whoAmI;
  final calls = <int?>[];

  @override
  Future<ProfileDetail> getMyProfile() async {
    final id = _whoAmI();
    calls.add(id);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return ProfileDetail.fromJson({'id': id, 'name': 'user-$id'});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late ProviderContainer container;
  late _FakeProfileRepository repo;

  setUp(() {
    repo = _FakeProfileRepository(() => container.read(authScopeProvider));
    container = ProviderContainer(overrides: [
      profileRepositoryProvider.overrideWithValue(repo),
      // The real one needs a live Dio; nothing in this test touches it.
      dioProvider.overrideWithValue(Dio()),
    ]);
  });

  tearDown(() => container.dispose());

  test('switching accounts refetches instead of serving the previous profile', () async {
    container.read(authScopeProvider.notifier).setUserId(42);
    final sub = container.listen(myProfileProvider, (_, _) {});

    expect((await container.read(myProfileProvider.future)).name, 'user-42');

    container.read(authScopeProvider.notifier).setUserId(43);

    // The critical property: the previous account's profile must NOT be readable as
    // settled data while the new one loads. `.asData` is null during the reload — which is
    // why every screen must read through it, never through `.value`.
    expect(container.read(myProfileProvider).asData, isNull,
        reason: "account 42's profile is still being served as data after switching to 43");

    expect((await container.read(myProfileProvider.future)).name, 'user-43');
    expect(repo.calls, [42, 43], reason: 'the switch must trigger a fresh fetch');
    sub.close();
  });

  test('logging out drops the cached profile', () async {
    container.read(authScopeProvider.notifier).setUserId(42);
    final sub = container.listen(myProfileProvider, (_, _) {});
    expect((await container.read(myProfileProvider.future)).name, 'user-42');

    container.read(authScopeProvider.notifier).setUserId(null);
    expect(container.read(myProfileProvider).asData, isNull);
    sub.close();
  });

  test('refreshing the same account does not refetch', () async {
    container.read(authScopeProvider.notifier).setUserId(42);
    final sub = container.listen(myProfileProvider, (_, _) {});
    await container.read(myProfileProvider.future);

    // refreshUser() rebuilds AppUser but the id is unchanged — this must be a no-op, or
    // every profile refresh would throw away and refetch the whole cache.
    container.read(authScopeProvider.notifier).setUserId(42);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(repo.calls, [42]);
    sub.close();
  });
}
