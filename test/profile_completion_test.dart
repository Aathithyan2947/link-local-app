import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/router/app_router.dart' show appRouteObserver;
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/address/data/address_models.dart';
import 'package:link_local/features/address/data/address_repository.dart';
import 'package:link_local/features/address/presentation/address_proof_screen.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/business/data/business_repository.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/home/presentation/tabs/profile_tab.dart';
import 'package:link_local/features/messages/data/messages_repository.dart' show conversationsProvider;
import 'package:link_local/features/orders/data/orders_repository.dart';
import 'package:link_local/features/orders/data/transaction_counts.dart';
import 'package:link_local/features/profile/data/profile_completion.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';
import 'package:link_local/features/profile/presentation/profile_completion_screen.dart';

class _Provider extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 60, userType: 'service_provider', name: 'Aathithyan'),
      );
}

class _Resident extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 61, userType: 'resident', name: 'Ravi'),
      );
}

class _SeenPending extends PaymentsSeenAt {
  @override
  Future<DateTime> build() => Completer<DateTime>().future;
}

/// What GET /profiles/me/completion answers; [answer] changes as the member fills things in.
class _Server {
  _Server(this.answer);
  ProfileCompletion? answer;
  Object? error;
  int fetches = 0;

  Future<ProfileCompletion> fetch() async {
    fetches++;
    if (error != null) throw error!;
    return answer ?? Completer<ProfileCompletion>().future;
  }
}

ProfileCompletion _completion(Map<String, bool> steps) {
  final done = steps.values.where((d) => d).length;
  return ProfileCompletion.fromJson({
    'percent': (done / steps.length * 100).round(),
    'profileId': 8,
    'items': [
      for (final e in steps.entries) {'key': e.key, 'label': e.key, 'done': e.value},
    ],
  });
}

/// A home baker with 6 of 9 done: photo, address proof and menu items to go.
final _sixOfNine = _completion({
  'photo': false,
  'address': true,
  'addressProof': false,
  'about': true,
  'education': true,
  'profession': true,
  'services': true,
  'businessDetails': true,
  'menuItems': false,
});

Future<void> _pumpProfileTab(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1170, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final never = Completer<Never>().future;
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_Provider.new),
      myOrdersProvider.overrideWith((ref) async => const []),
      conversationsProvider.overrideWith((ref) async => const []),
      paymentsSeenAtProvider.overrideWith(_SeenPending.new),
      myProfileProvider.overrideWith((ref) => never),
      myProviderFeaturesProvider.overrideWith((ref) => never),
      myAvailabilityProvider.overrideWith((ref) => never),
      myAddressProofProvider.overrideWith((ref) async => const AddressProofInfo(hasAddress: true, addressId: 4, status: 'none')),
      profileCompletionProvider.overrideWith((ref) => server.fetch()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      navigatorObservers: [appRouteObserver],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileTab())),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

double _barValue(WidgetTester tester) =>
    tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first).value!;

void main() {
  group('Profile completion meter on the Profile tab', () {
    testWidgets('sits under the profile card and above My Shop, with the next step', (tester) async {
      await _pumpProfileTab(tester, _Server(_sixOfNine));

      expect(find.text('Profile 67% complete'), findsOneWidget);
      expect(_barValue(tester), closeTo(0.67, 0.001));
      expect(find.text('Next: Add a profile photo'), findsOneWidget, reason: 'the first step still to do');

      final meter = tester.getTopLeft(find.text('Profile 67% complete')).dy;
      expect(meter, greaterThan(tester.getTopLeft(find.text('Edit')).dy), reason: 'below the user card');
      expect(meter, lessThan(tester.getTopLeft(find.text('My Shop')).dy), reason: 'above My Shop');
    });

    testWidgets('at 100% it stays, saying the profile is complete', (tester) async {
      await _pumpProfileTab(tester, _Server(_completion({'photo': true, 'address': true, 'addressProof': true})));
      expect(find.text('Your profile is complete'), findsOneWidget);
      expect(_barValue(tester), 1.0);
      expect(find.textContaining('Next:'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets("nothing shows while it loads or if it can't load: the tab works without it", (tester) async {
      await _pumpProfileTab(tester, _Server(null));
      expect(find.textContaining('complete'), findsNothing);
      expect(find.text('My Shop'), findsOneWidget);
    });

    testWidgets('a failed load hides it too', (tester) async {
      await _pumpProfileTab(tester, _Server(_sixOfNine)..error = Exception('offline'));
      expect(find.textContaining('complete'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a tap opens the checklist: every step, done or what to do', (tester) async {
      await _pumpProfileTab(tester, _Server(_sixOfNine));
      await tester.tap(find.text('Profile 67% complete'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileCompletionScreen), findsOneWidget);
      expect(find.text('67% complete'), findsOneWidget);
      for (final title in [
        'Profile photo',
        'Address',
        'Address proof',
        'About you',
        'Education',
        'Profession',
        'Services',
        'Business details',
        'Menu items',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Done'), findsNWidgets(6));
      expect(find.text('Upload your address proof'), findsOneWidget);
      expect(find.text('Add your first menu item'), findsOneWidget);
    });

    testWidgets('a step opens where it is filled in, and coming back refreshes the meter', (tester) async {
      final server = _Server(_sixOfNine);
      await _pumpProfileTab(tester, server);
      await tester.tap(find.text('Profile 67% complete'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Address proof'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressProofScreen), findsOneWidget);

      // They upload it, then come back: the checklist and the meter both catch up.
      server.answer = _completion({
        'photo': false,
        'address': true,
        'addressProof': true,
        'about': true,
        'education': true,
        'profession': true,
        'services': true,
        'businessDetails': true,
        'menuItems': false,
      });
      final before = server.fetches;
      Navigator.of(tester.element(find.byType(AddressProofScreen))).pop();
      await tester.pumpAndSettle();
      expect(server.fetches, greaterThan(before));
      expect(find.text('78% complete'), findsOneWidget);

      Navigator.of(tester.element(find.byType(ProfileCompletionScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Profile 78% complete'), findsOneWidget);
      expect(find.text('Next: Add a profile photo'), findsOneWidget);
    });

    testWidgets('photo opens My Profile, by the id the checklist came with', (tester) async {
      await _pumpProfileTab(tester, _Server(_sixOfNine));
      await tester.tap(find.text('Profile 67% complete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<ServiceProviderDetailScreen>(find.byType(ServiceProviderDetailScreen)).id, 8);
    });

    // On iOS a lazy ListView kept its old length after the meter grew in, so the tab stopped
    // short of Log Out at these heights (a resident's tab; seen on an iPhone 17 Pro).
    for (final height in [900, 950, 1000, 1050, 1100, 1150]) {
      testWidgets('Log Out stays reachable on iOS once the meter loads (screen $height pt)', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        tester.view.physicalSize = Size(1206, height * 3.0);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          retry: (_, _) => null,
          overrides: [
            dioProvider.overrideWithValue(Dio()),
            authControllerProvider.overrideWith(_Resident.new),
            myOrdersProvider.overrideWith((ref) async => const []),
            conversationsProvider.overrideWith((ref) async => const []),
            paymentsSeenAtProvider.overrideWith(_SeenPending.new),
            myProfileProvider.overrideWith((ref) => Completer<Never>().future),
            myProviderFeaturesProvider.overrideWith((ref) => Completer<Never>().future),
            myAvailabilityProvider.overrideWith((ref) => Completer<Never>().future),
            profileCompletionProvider.overrideWith((ref) async {
              await Future<void>.delayed(const Duration(milliseconds: 300));
              return _completion({'photo': false, 'address': true, 'addressProof': false});
            }),
          ],
          child: MaterialApp(theme: AppTheme.light, navigatorObservers: [appRouteObserver], home: const ProfileTab()),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('Profile 33% complete'), findsOneWidget);

        await tester.fling(find.byType(SingleChildScrollView), const Offset(0, -3000), 3000);
        await tester.pumpAndSettle();
        final logOut = tester.getRect(find.text('Log Out'));
        debugDefaultTargetPlatformOverride = null;
        expect(logOut.bottom, lessThanOrEqualTo(height.toDouble()), reason: 'Log Out on screen at the end');
      });
    }

    test('reads the server answer, with any step this build does not know', () {
      final c = ProfileCompletion.fromJson({
        'percent': 50,
        'profileId': 3,
        'items': [
          {'key': 'photo', 'label': 'Profile photo', 'done': true},
          {'key': 'somethingNew', 'label': 'Something new', 'done': false},
        ],
      });
      expect(c.percent, 50);
      expect(c.profileId, 3);
      expect(c.isComplete, isFalse);
      expect(c.next!.key, 'somethingNew');
      expect(completionStepHint(c.next!), 'Add your something new');
      expect(ProfileCompletion.fromJson({'percent': 140, 'items': []}).percent, 100);
    });
  });
}
