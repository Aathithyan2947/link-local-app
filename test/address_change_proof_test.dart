import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:link_local/core/auth/auth_scope.dart';
import 'package:link_local/core/location/location_models.dart';
import 'package:link_local/core/location/location_providers.dart';
import 'package:link_local/core/location/location_service.dart';
import 'package:link_local/core/network/api_exception.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/router/app_router.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/address/data/address_models.dart';
import 'package:link_local/features/address/data/address_repository.dart';
import 'package:link_local/features/address/presentation/address_capture_screen.dart';
import 'package:link_local/features/address/presentation/address_proof_gate.dart';
import 'package:link_local/features/address/presentation/address_proof_screen.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/auth/data/auth_repository.dart';
import 'package:link_local/features/business/data/business_repository.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';
import 'package:link_local/features/home/data/profile_congrats.dart';
import 'package:link_local/features/home/presentation/home_feed_screen.dart';
import 'package:link_local/features/members/data/members_repository.dart';
import 'package:link_local/features/notifications/data/notifications_repository.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';
import 'package:link_local/features/reference/reference_models.dart';
import 'package:link_local/features/reference/reference_repository.dart';
import 'package:link_local/features/services/data/service_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _thane = City(id: 1, name: 'Thane', state: 'Maharashtra');

/// Asha, signed in; verified for the address she had when the session started.
class _Asha extends AuthController {
  _Asha({this.verified = true});
  final bool verified;
  @override
  AuthState build() => AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 5, userType: 'resident', name: 'Asha', hasAddress: true, isVerified: verified),
      );
}

/// The account id the caches are bound to, as the auth controller publishes it on sign-in.
class _SignedIn extends AuthScope {
  @override
  int? build() => 5;
}

/// `/auth/me`: the server unverified Asha when she moved, or the request fails.
class _Auth implements AuthRepository {
  _Auth({this.fails = false});
  final bool fails;
  int calls = 0;

  @override
  Future<AppUser> me() async {
    calls++;
    if (fails) throw ApiException('Your internet seems to be a bit wonky.');
    return const AppUser(id: 5, userType: 'resident', name: 'Asha', hasAddress: true);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// Address #41 with an approved proof, until the form saves a new one: #42, with no proof yet.
class _Addresses implements AddressRepository {
  int addressId = 41;
  String status = 'approved';
  final saved = <String>[];

  @override
  Future<List<CityAddressField>> getCityAddressFields(int cityId) async => const [];

  @override
  Future<void> createAddress({
    required int cityId,
    required String fullAddress,
    String? areaName,
    String? pincode,
    String? apartment,
    String? flatWing,
    String? suburb,
    String? lane1,
    String? lane2,
    double? latitude,
    double? longitude,
    double? accuracyM,
    String? locationSource,
    String? googlePlaceId,
  }) async {
    saved.add(fullAddress);
    addressId++;
    status = 'none';
  }

  @override
  Future<AddressProofInfo> getMyAddressProof() async =>
      AddressProofInfo(hasAddress: true, addressId: addressId, fullAddress: 'Flat 2, Pai Nagar', status: status);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// Location off, so the form never auto-detects a city.
class _NoLocation implements LocationService {
  @override
  Future<LocationPermissionOutcome> ensurePermission() async => LocationPermissionOutcome.denied;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

List<Override> _addressOverrides(_Auth auth, _Addresses addresses) => [
      dioProvider.overrideWithValue(Dio()),
      authScopeProvider.overrideWith(_SignedIn.new),
      authRepositoryProvider.overrideWithValue(auth),
      addressRepositoryProvider.overrideWithValue(addresses),
      citiesProvider.overrideWith((ref) async => const [_thane]),
      myProfileProvider.overrideWith((ref) async => ProfileDetail.fromJson({
            'id': 67,
            'name': 'Asha',
            'address': {
              'fullAddress': 'Flat 2, Pai Nagar',
              'area': {
                'city': {'id': 1},
              },
            },
          })),
      locationServiceProvider.overrideWithValue(_NoLocation()),
    ];

/// My Profile, reduced to the pencil by the address and an action the proof gates. Changes
/// the address and lands on the proof screen.
Future<List<bool>> _changeAddress(WidgetTester tester, _Auth auth, _Addresses addresses) async {
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final results = <bool>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ..._addressOverrides(auth, addresses),
      authControllerProvider.overrideWith(_Asha.new),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Column(children: [
            TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AddressCaptureScreen(editing: true))),
              child: const Text('Change address'),
            ),
            TextButton(
              onPressed: () async => results.add(await ensureAddressProof(context, ref, action: 'submit a review')),
              child: const Text('Review'),
            ),
          ]),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Change address'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
  return results;
}

AuthState _auth(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first)).read(authControllerProvider);

/// Home warms the share sheet's directory; nobody's in it here.
class _NoMembers implements MembersRepository {
  @override
  Future<MembersPage> list({required String scope, int? areaId, String? q, int page = 1, int pageSize = 30}) async =>
      const MembersPage(items: [], total: 0);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

HomeFeed _feed() => HomeFeed.fromJson({
      'city': {'id': 1, 'name': 'Thane'},
      'stats': {'members': 3, 'serviceProviders': 0, 'events': 0},
      'discussions': [],
      'groups': {'total': 0, 'items': []},
      'workshops': {'total': 0, 'items': []},
      'serviceProviders': {'total': 0, 'items': [], 'services': []},
    });

/// Home for Asha, whose current address is [address] with no proof, loaded after [lag]. The
/// reminder's dismissal is the real one, in (mock) secure storage that outlives each pump.
Future<void> _pumpHome(WidgetTester tester, int Function() address,
    {Duration lag = Duration.zero, bool verified = false}) async {
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    // A fresh scope per pump: a relaunch, with nothing cached.
    key: UniqueKey(),
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(() => _Asha(verified: verified)),
      authScopeProvider.overrideWith(_SignedIn.new),
      homeFeedProvider.overrideWith((ref) async => _feed()),
      myProfileProvider.overrideWith((ref) => Completer<ProfileDetail>().future),
      myAddressProofProvider.overrideWith((ref) async {
        await Future<void>.delayed(lag);
        return AddressProofInfo(hasAddress: true, addressId: address(), status: 'none');
      }),
      profileCongratsShownProvider.overrideWith((ref) async => true),
      customFieldsProvider.overrideWith((ref) async => const []),
      myProviderFeaturesProvider.overrideWith((ref) async => (hasMenu: false, hasDateBooking: false)),
      unreadCountProvider.overrideWith((ref) async => 0),
      membersRepositoryProvider.overrideWithValue(_NoMembers()),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const HomeFeedScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('BUG-103: changing address asks for a proof again', () {
    testWidgets('the signed-in user is re-read, so actions ask for the new proof straight away', (tester) async {
      final auth = _Auth();
      final addresses = _Addresses();
      final results = await _changeAddress(tester, auth, addresses);

      expect(addresses.saved, ['Thane, Maharashtra']);
      expect(find.byType(AddressProofScreen), findsOneWidget, reason: 'straight on to proving the new address');
      expect(find.text('Not uploaded'), findsOneWidget);
      expect(auth.calls, 1);
      expect(_auth(tester).user!.isVerified, isFalse, reason: 'the verification belonged to the old address');

      // Not now: the member may leave the proof screen (block actions, not accounts)...
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AddressProofScreen), findsNothing);

      // ...but the next gated action asks for the proof, without waiting for a restart.
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Address proof mandatory'), findsOneWidget);
      expect(find.text('Upload your address proof to submit a review.'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });

    testWidgets("a failed refresh doesn't sign the member out or hold up the proof screen", (tester) async {
      final auth = _Auth(fails: true);
      await _changeAddress(tester, auth, _Addresses());

      expect(auth.calls, 1);
      expect(find.byType(AddressProofScreen), findsOneWidget);
      expect(_auth(tester).status, AuthStatus.authenticated);
      expect(_auth(tester).user?.id, 5);
    });

    testWidgets('the first address at sign-up carries on to the verify step as before', (tester) async {
      tester.view.physicalSize = const Size(1800, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final auth = _Auth();
      final addresses = _Addresses();
      final router = GoRouter(initialLocation: Routes.address, routes: [
        GoRoute(path: Routes.address, builder: (_, _) => const AddressCaptureScreen()),
        GoRoute(path: Routes.verifyAddress, builder: (_, _) => const Scaffold(body: Text('Verify step'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._addressOverrides(auth, addresses),
          authControllerProvider.overrideWith(() => _Asha(verified: false)),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<City>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thane, Maharashtra').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(addresses.saved, ['Thane, Maharashtra']);
      expect(find.text('Verify step'), findsOneWidget);
      expect(find.byType(AddressProofScreen), findsNothing);
      expect(auth.calls, 0, reason: 'onboarding refreshes the user later, when the role is picked');
    });
  });

  group('BUG-103: the Home proof reminder', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    testWidgets('dismissed for one address it stays dismissed there, and comes back for the next',
        (tester) async {
      var address = 41;
      await _pumpHome(tester, () => address);
      expect(find.text('Upload your address proof'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Upload your address proof'), findsNothing);

      await _pumpHome(tester, () => address);
      expect(find.text('Upload your address proof'), findsNothing, reason: 'still dismissed for #41 after a relaunch');

      // The member moves: the profile invalidates the proof status, which now describes #42.
      address = 42;
      ProviderScope.containerOf(tester.element(find.byType(HomeFeedScreen))).invalidate(myAddressProofProvider);
      await tester.pumpAndSettle();
      expect(find.text('Upload your address proof'), findsOneWidget, reason: '#42 needs its own proof');

      address = 41;
      await _pumpHome(tester, () => address);
      expect(find.text('Upload your address proof'), findsNothing, reason: 'the dismissal for #41 is untouched');
    });

    testWidgets('a member the admin verified, with no proof uploaded, is not asked for one', (tester) async {
      await _pumpHome(tester, () => 41, verified: true);
      expect(find.text('Upload your address proof'), findsNothing, reason: 'the action gate lets them through too');
    });

    testWidgets("doesn't blink while the proof status reloads", (tester) async {
      await _pumpHome(tester, () => 41, lag: const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Upload your address proof'), findsOneWidget);

      // Back from the proof screen without uploading: Home reloads the status, same address.
      ProviderScope.containerOf(tester.element(find.byType(HomeFeedScreen))).invalidate(myAddressProofProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Upload your address proof'), findsOneWidget, reason: 'the dismissal reloads with it');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Upload your address proof'), findsOneWidget);
    });
  });
}
