import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      // Still bootstrapping → keep showing the splash.
      if (auth.status == AuthStatus.unknown) {
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
        // Logged out: stay on an auth screen, otherwise (incl. splash) go to onboarding.
        return authScreens.contains(loc) ? null : Routes.onboarding;
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
