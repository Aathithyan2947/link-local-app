import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../storage/intro_seen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/role_selection_screen.dart';
import '../../features/auth/presentation/verification_hold_screen.dart';
import '../../features/address/presentation/address_capture_screen.dart';
import '../../features/address/presentation/address_verify_screen.dart';
import '../../features/services/presentation/service_category_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/splash/splash_screen.dart';

abstract class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const register = '/register';
  static const otp = '/otp';
  static const address = '/address';
  static const verifyAddress = '/verify-address';
  static const roleSelection = '/role-selection';
  static const serviceCategory = '/service-category';
  static const verificationHold = '/verification-hold';
  static const home = '/home';
}

/// Watches route transitions app-wide. A screen subscribes with [RouteAware] to refresh
/// itself in `didPopNext()` — when an editor pushed on top of it closes — instead of every
/// edit site having to remember to invalidate the right provider.
final appRouteObserver = AppRouteObserver();

class AppRouteObserver extends RouteObserver<ModalRoute<void>> {
  /// The route that closed most recently, so `didPopNext()` can tell an editor (a page or a
  /// bottom sheet, which may have changed things) from a menu or confirm dialog (which didn't).
  Route<dynamic>? lastPopped;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPopped = route;
    super.didPop(route, previousRoute);
  }
}

/// True when the route that just closed was a menu or dialog rather than an editor.
bool lastPopWasMenuOrDialog() {
  final r = appRouteObserver.lastPopped;
  return r is PopupRoute && r is! ModalBottomSheetRoute;
}

/// The step a member with an address skipped by quitting sign-up, when [loc] isn't part of
/// finishing it; null otherwise. The address is saved before the role and services steps, so
/// quitting after it used to land on Home (BUG-095): as a resident who never chose a role, or
/// as a provider with no services.
String? unfinishedSignupRedirect(AuthState auth, String loc) {
  if (auth.signupUnfinished) {
    const signupSteps = {Routes.address, Routes.verifyAddress, Routes.roleSelection, Routes.serviceCategory};
    return signupSteps.contains(loc) ? null : Routes.roleSelection;
  }
  if (auth.user?.isServiceProvider == true && auth.user?.hasServices == false) {
    return loc == Routes.serviceCategory || loc == Routes.roleSelection ? null : Routes.serviceCategory;
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(introSeenProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    // Lets a screen know when a route pushed on top of it was popped, so it can refetch what
    // an editor may have changed. See ServiceProviderDetailScreen.
    observers: [appRouteObserver],
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final introSeen = ref.read(introSeenProvider);
      final loc = state.matchedLocation;

      // Still bootstrapping (session restore, or the introduction flag) → keep the splash.
      if (auth.status == AuthStatus.unknown || introSeen == null) {
        return loc == Routes.splash ? null : Routes.splash;
      }

      final loggedIn = auth.status == AuthStatus.authenticated;
      // Auth screens a logged-out user is allowed to sit on. Splash is NOT here:
      // once bootstrap finishes, we must always move off the splash screen.
      final authScreens = {
        Routes.onboarding,
        Routes.login,
        Routes.register,
        Routes.otp,
      };

      if (!loggedIn) {
        // Logged out: stay on an auth screen; otherwise (incl. splash, and after a logout) go
        // to Login — or to the introduction on a device that has never been through it.
        if (authScreens.contains(loc)) return null;
        return introSeen ? Routes.login : Routes.onboarding;
      }

      // Logged in but address not yet captured → push the onboarding-address flow.
      final needsAddress = !(auth.user?.hasAddress ?? false);
      final onAddressFlow = {
        Routes.address,
        Routes.verifyAddress,
        Routes.roleSelection,
        Routes.serviceCategory,
      }.contains(loc);

      if (needsAddress) {
        return onAddressFlow ? null : Routes.address;
      }
      if (unfinishedSignupRedirect(auth, loc) case final String step) return step;

      // Fully onboarded → leave splash/auth screens for home.
      if (loc == Routes.splash || authScreens.contains(loc)) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: Routes.otp,
        builder: (_, state) {
          final args = state.extra as OtpArgs?;
          return args == null ? const LoginScreen() : OtpScreen(args: args);
        },
      ),
      GoRoute(path: Routes.address, builder: (_, _) => const AddressCaptureScreen()),
      GoRoute(path: Routes.verifyAddress, builder: (_, _) => const AddressVerifyScreen()),
      GoRoute(path: Routes.roleSelection, builder: (_, _) => const RoleSelectionScreen()),
      GoRoute(path: Routes.serviceCategory, builder: (_, _) => const ServiceCategoryScreen()),
      GoRoute(path: Routes.verificationHold, builder: (_, _) => const VerificationHoldScreen()),
      GoRoute(path: Routes.home, builder: (_, _) => const HomeShell()),
    ],
  );
});
