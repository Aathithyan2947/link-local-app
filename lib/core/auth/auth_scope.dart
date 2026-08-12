import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The id of the account whose data is currently cached — null when logged out.
///
/// Every provider holding user-scoped data watches this, so switching accounts (or logging
/// out) disposes it and it refetches for the new identity. That replaces the hand-maintained
/// invalidate-list this app used to keep in the auth controller, which had drifted to cover
/// only a third of the providers and left the rest rendering the previous account's data.
///
/// Reference data (cities, service categories, the profile masters) deliberately does NOT
/// watch this — it's identical for everyone and shouldn't be refetched on every login.
///
/// Lives in `core` so data-layer providers can depend on it without reaching up into the auth
/// feature. [AuthController] is the only writer.
class AuthScope extends Notifier<int?> {
  @override
  int? build() => null;

  /// No-ops when the id is unchanged, so refreshing the current user (which builds a new
  /// AppUser object) doesn't needlessly throw away and refetch everything.
  void setUserId(int? userId) {
    if (state != userId) state = userId;
  }
}

final authScopeProvider = NotifierProvider<AuthScope, int?>(AuthScope.new);

extension AuthScopeRef on Ref {
  /// Ties this provider's cache to the signed-in account: Riverpod disposes it when the
  /// account changes, so it can never serve the previous user's data. Call it first thing in
  /// any provider whose value depends on who is logged in — including `.family` ones, where
  /// every keyed entry is dropped together.
  ///
  /// A provider that would be *restored* rather than discarded (the cart) should watch
  /// [authScopeProvider] directly and reload for the new id instead of calling this.
  void bindToAccount() => watch(authScopeProvider);
}
