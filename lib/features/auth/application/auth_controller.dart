import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/token_storage.dart';
import '../../address/data/address_repository.dart';
import '../../business/data/business_repository.dart';
import '../../home/data/doc_reminder.dart';
import '../../home/data/home_repository.dart';
import '../../home/data/profile_congrats.dart';
import '../../messages/data/messages_repository.dart' as messages;
import '../../notifications/data/notifications_repository.dart' as notifications;
import '../../orders/data/orders_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../services/data/service_profile_repository.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({this.status = AuthStatus.unknown, this.user});
  final AuthStatus status;
  final AppUser? user;

  AuthState copyWith({AuthStatus? status, AppUser? user}) =>
      AuthState(status: status ?? this.status, user: user ?? this.user);

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

class AuthController extends Notifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);
  TokenStorage get _tokens => ref.read(tokenStorageProvider);

  /// Clears every cached user-scoped provider so a freshly-authenticated (or freshly
  /// logged-out) session never renders stale data left over from a previous account —
  /// these are plain (non-family, non-autoDispose) FutureProviders/Notifiers that Riverpod
  /// otherwise keeps resolved for the whole ProviderContainer lifetime.
  void _invalidateUserScopedProviders() {
    ref.invalidate(homeFeedProvider);
    ref.invalidate(homeScopeProvider);
    ref.invalidate(spSectionAreaProvider);
    ref.invalidate(workshopsSectionAreaProvider);
    ref.invalidate(groupsSectionAreaProvider);
    ref.invalidate(myProfileProvider);
    ref.invalidate(myAddressProofProvider);
    ref.invalidate(docReminderDismissedProvider);
    ref.invalidate(profileCongratsShownProvider);
    ref.invalidate(notifications.unreadCountProvider);
    ref.invalidate(messages.unreadCountProvider);
    ref.invalidate(myRatesProvider);
    ref.invalidate(myProviderKindProvider);
    ref.invalidate(myProviderFeaturesProvider);
    ref.invalidate(myOrdersProvider);
    ref.invalidate(customFieldsProvider);
  }

  @override
  AuthState build() {
    _bootstrap();
    return const AuthState();
  }

  Future<void> _bootstrap() async {
    final token = await _tokens.accessToken;
    if (token == null || token.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await _repo.me();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      await _tokens.clear();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login({required String identifier, required String password}) async {
    final result = await _repo.login(identifier: identifier, password: password);
    await _tokens.save(accessToken: result.accessToken, refreshToken: result.refreshToken);
    // Re-fetch full profile (so we know whether the address step is complete).
    final user = await _repo.me();
    state = AuthState(status: AuthStatus.authenticated, user: user);
    _invalidateUserScopedProviders();
  }

  Future<void> register({
    required String name,
    required String password,
    String? email,
    String? mobile,
    String userType = 'resident',
    String? referralCode,
    int? referralSourceId,
  }) async {
    final result = await _repo.register(
      name: name,
      password: password,
      email: email,
      mobile: mobile,
      userType: userType,
      referralCode: referralCode,
      referralSourceId: referralSourceId,
    );
    await _tokens.save(accessToken: result.accessToken, refreshToken: result.refreshToken);
    state = AuthState(status: AuthStatus.authenticated, user: result.user);
    _invalidateUserScopedProviders();
  }

  Future<String?> requestOtp({
    String? mobile,
    String? email,
    required String purpose,
    String? name,
  }) {
    return _repo.requestOtp(mobile: mobile, email: email, purpose: purpose, name: name);
  }

  Future<void> verifyOtp({
    String? mobile,
    String? email,
    required String otp,
    required String purpose,
    String? name,
    String? referralCode,
    int? referralSourceId,
  }) async {
    final result = await _repo.verifyOtp(
      mobile: mobile,
      email: email,
      otp: otp,
      purpose: purpose,
      name: name,
      referralCode: referralCode,
      referralSourceId: referralSourceId,
    );
    await _tokens.save(accessToken: result.accessToken, refreshToken: result.refreshToken);
    final user = await _repo.me();
    state = AuthState(status: AuthStatus.authenticated, user: user);
    _invalidateUserScopedProviders();
  }

  /// Sets resident vs service_provider (after address, per PRD) and refreshes.
  Future<void> setUserType(String userType) async {
    await _repo.setUserType(userType);
    await refreshUser();
  }

  /// Refreshes the cached user (e.g. after completing the address step).
  Future<void> refreshUser() async {
    try {
      final user = await _repo.me();
      state = state.copyWith(status: AuthStatus.authenticated, user: user);
    } catch (_) {/* keep current state */}
  }

  Future<void> logout() async {
    await _tokens.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
    _invalidateUserScopedProviders();
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
