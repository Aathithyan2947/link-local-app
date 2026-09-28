import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/router/app_router.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/presentation/login_screen.dart';
import 'package:link_local/features/onboarding/presentation/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signed out, without touching token storage or the network.
class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

Future<void> _launch(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [authControllerProvider.overrideWith(_SignedOut.new)],
    child: Consumer(builder: (_, ref, _) => MaterialApp.router(routerConfig: ref.watch(routerProvider))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a device that has seen the introduction lands on Login when signed out', (tester) async {
    SharedPreferences.setMockInitialValues({'ll_intro_seen': true});
    await _launch(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('a fresh install still gets the introduction', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _launch(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
