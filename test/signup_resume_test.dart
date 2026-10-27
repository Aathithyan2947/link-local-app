import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/router/app_router.dart';
import 'package:link_local/core/storage/intro_seen.dart';
import 'package:link_local/core/storage/token_storage.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/auth/data/auth_repository.dart';
import 'package:link_local/features/auth/presentation/role_selection_screen.dart';
import 'package:link_local/features/reference/reference_models.dart';
import 'package:link_local/features/reference/reference_repository.dart';
import 'package:link_local/features/services/presentation/service_category_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _address = {
  'id': 1,
  'fullAddress': 'Flat 2, Pai Nagar',
  'area': {
    'areaName': 'Pai Nagar',
    'city': {'name': 'Mumbai'},
  },
};

/// `/auth/me` for user 5 with an address; [serviceTypeCount] as the backend sends it.
AppUser _me({String userType = 'resident', Object? serviceTypeCount, bool withAddress = true}) => AppUser.fromJson({
      'id': 5,
      'userType': userType,
      'profile': {
        'name': 'Asha',
        'address': withAddress ? _address : null,
        'serviceTypeCount': ?serviceTypeCount,
      },
    });

AuthState _signedIn(AppUser user, {bool signupUnfinished = false}) =>
    AuthState(status: AuthStatus.authenticated, user: user, signupUnfinished: signupUnfinished);

class _Tokens implements TokenStorage {
  String? token;
  @override
  Future<String?> get accessToken async => token;
  @override
  Future<void> save({required String accessToken, required String refreshToken}) async => token = accessToken;
  @override
  Future<void> clear() async => token = null;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// A backend with one account (user 5): signs up, then saves an address.
class _Server implements AuthRepository {
  AppUser account = _me(withAddress: false);

  @override
  Future<AuthResult> register({
    required String name,
    required String password,
    String? email,
    String? mobile,
    String userType = 'resident',
    String? referralCode,
    int? referralSourceId,
  }) async =>
      AuthResult(user: account, accessToken: 'a', refreshToken: 'r');
  @override
  Future<AppUser> me() async => account;
  @override
  Future<void> setUserType(String userType) async =>
      account = _me(userType: userType, serviceTypeCount: 0);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// Past the introduction already, so nothing is still loading it when a test "kills the app".
class _IntroSeen extends IntroSeen {
  @override
  bool? build() => true;
}

Future<AuthState> _launch(ProviderContainer c) async {
  c.read(authControllerProvider);
  for (var i = 0; i < 20 && c.read(authControllerProvider).status == AuthStatus.unknown; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return c.read(authControllerProvider);
}

class _Fixed extends AuthController {
  _Fixed(this._state);
  final AuthState _state;
  @override
  AuthState build() => _state;
}

Future<void> _openApp(WidgetTester tester, AuthState auth) async {
  SharedPreferences.setMockInitialValues({'ll_intro_seen': true});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _Fixed(auth)),
      serviceCategoriesProvider.overrideWith((ref) async => const [
            ServiceCategory(id: 1, name: 'Fitness', subcategories: [
              ServiceSubcategory(id: 11, name: 'Yoga instructor', categoryId: 1),
            ]),
          ]),
    ],
    child: Consumer(
      builder: (_, ref, _) => MaterialApp.router(theme: AppTheme.light, routerConfig: ref.watch(routerProvider)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('BUG-095: whether a provider has services', () {
    test('comes from the profile service count', () {
      expect(_me(serviceTypeCount: 0).hasServices, isFalse);
      expect(_me(serviceTypeCount: 2).hasServices, isTrue);
    });

    test('is unknown when the server does not say, which must never redirect anyone', () {
      final user = _me(userType: 'service_provider');
      expect(user.hasServices, isNull);
      expect(unfinishedSignupRedirect(_signedIn(user), Routes.home), isNull);
    });
  });

  group('BUG-095: unfinishedSignupRedirect', () {
    final noServices = _signedIn(_me(userType: 'service_provider', serviceTypeCount: 0));

    test('a provider with no services goes back to the services step', () {
      expect(unfinishedSignupRedirect(noServices, Routes.splash), Routes.serviceCategory);
      expect(unfinishedSignupRedirect(noServices, Routes.home), Routes.serviceCategory);
      expect(unfinishedSignupRedirect(noServices, Routes.verificationHold), Routes.serviceCategory);
    });

    test('and may stay on it, or go back to change role', () {
      expect(unfinishedSignupRedirect(noServices, Routes.serviceCategory), isNull);
      expect(unfinishedSignupRedirect(noServices, Routes.roleSelection), isNull);
    });

    test('a provider with services, and a resident, are left alone', () {
      expect(unfinishedSignupRedirect(_signedIn(_me(userType: 'service_provider', serviceTypeCount: 1)), Routes.home),
          isNull);
      expect(unfinishedSignupRedirect(_signedIn(_me(serviceTypeCount: 0)), Routes.home), isNull);
    });

    test('someone who never picked a role goes back to the role step', () {
      final unfinished = _signedIn(_me(serviceTypeCount: 0), signupUnfinished: true);
      expect(unfinishedSignupRedirect(unfinished, Routes.splash), Routes.roleSelection);
      expect(unfinishedSignupRedirect(unfinished, Routes.home), Routes.roleSelection);
      for (final step in [Routes.verifyAddress, Routes.roleSelection, Routes.serviceCategory]) {
        expect(unfinishedSignupRedirect(unfinished, step), isNull, reason: '$step is part of finishing sign-up');
      }
    });
  });

  test('BUG-095: a new account resumes at the role step after a relaunch, until a role is saved', () async {
    SharedPreferences.setMockInitialValues({});
    final server = _Server();
    final tokens = _Tokens();
    ProviderContainer open() => ProviderContainer(overrides: [
          authRepositoryProvider.overrideWithValue(server),
          tokenStorageProvider.overrideWithValue(tokens),
          introSeenProvider.overrideWith(_IntroSeen.new),
        ]);

    var app = open();
    expect((await _launch(app)).status, AuthStatus.unauthenticated);
    await app.read(authControllerProvider.notifier).register(name: 'Asha', password: 'Secret#123', mobile: '9876543210');
    expect(app.read(authControllerProvider).signupUnfinished, isTrue);
    app.dispose();

    // The address is saved, then the app is killed on the proof or role screen.
    server.account = _me(serviceTypeCount: 0);
    app = open();
    var state = await _launch(app);
    expect(state.signupUnfinished, isTrue);
    expect(unfinishedSignupRedirect(state, Routes.home), Routes.roleSelection);

    await app.read(authControllerProvider.notifier).setUserType('service_provider');
    state = app.read(authControllerProvider);
    expect(state.signupUnfinished, isFalse);
    expect(unfinishedSignupRedirect(state, Routes.home), Routes.serviceCategory,
        reason: 'a provider who then quits on the services step is caught by the service count');
    app.dispose();

    app = open();
    expect((await _launch(app)).signupUnfinished, isFalse, reason: 'the role is saved, so it is never asked again');
    app.dispose();
  });

  testWidgets('BUG-095: a provider with no services opens the app on the services step, not Home', (tester) async {
    await _openApp(tester, _signedIn(_me(userType: 'service_provider', serviceTypeCount: 0)));
    expect(find.byType(ServiceCategoryScreen), findsOneWidget);
    expect(find.text('Yoga instructor'), findsOneWidget);
  });

  testWidgets('BUG-095: someone who quit before picking a role opens the app on the role step', (tester) async {
    await _openApp(tester, _signedIn(_me(serviceTypeCount: 0), signupUnfinished: true));
    expect(find.byType(RoleSelectionScreen), findsOneWidget);
  });
}
