import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_scope.dart';
import '../../../core/storage/token_storage.dart';
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

  /// The single place auth state is assigned, so [authScopeProvider] can never fall out of
  /// step with it. Everything user-scoped hangs off that scope: publishing the new identity
  /// here disposes the previous account's cached providers, which is what keeps a fresh login
  /// from rendering the last account's profile, shop, chats or orders.
  void _setAuthState(AuthState next) {
    state = next;
    ref.read(authScopeProvider.notifier).setUserId(next.user?.id);
  }

  @override
  AuthState build() {
    _bootstrap();
    return const AuthState();
  }

  Future<void> _bootstrap() async {
    final token = await _tokens.accessToken;
    if (token == null || token.isEmpty) {
      _setAuthState(const AuthState(status: AuthStatus.unauthenticated));
      return;
    }
    try {
      final user = await _repo.me();
      _setAuthState(AuthState(status: AuthStatus.authenticated, user: user));
    } catch (_) {
      await _tokens.clear();
      _setAuthState(const AuthState(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> login({required String identifier, required String password}) async {
    final result = await _repo.login(identifier: identifier, password: password);
    await _tokens.save(accessToken: result.accessToken, refreshToken: result.refreshToken);
    // Re-fetch full profile (so we know whether the address step is complete).
    final user = await _repo.me();
    _setAuthState(AuthState(status: AuthStatus.authenticated, user: user));
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
    _setAuthState(AuthState(status: AuthStatus.authenticated, user: result.user));
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
    _setAuthState(AuthState(status: AuthStatus.authenticated, user: user));
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
      _setAuthState(state.copyWith(status: AuthStatus.authenticated, user: user));
    } catch (_) {/* keep current state */}
  }

  Future<void> logout() async {
    await _tokens.clear();
    _setAuthState(const AuthState(status: AuthStatus.unauthenticated));
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
