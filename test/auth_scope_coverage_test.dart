@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the fix for cross-account data leaking between sessions.
///
/// Every provider holding user-scoped data must tie its cache to the signed-in account, or it
/// keeps serving the previous user's data after a logout — Riverpod holds non-autoDispose
/// providers for the life of the container. This used to be enforced by a hand-maintained
/// invalidate-list in the auth controller, which drifted until it covered only a third of them.
///
/// A provider satisfies this by calling `ref.bindToAccount()` (reset on account change) or by
/// watching `authScopeProvider` directly (the cart, which is reloaded rather than discarded).
void main() {
  /// Files whose providers are account-bound. Reference/master data is deliberately absent:
  /// it's identical for every user and must not be refetched on each login.
  const userScopedFiles = [
    'lib/features/home/data/home_repository.dart',
    'lib/features/profile/data/profile_repository.dart',
    'lib/features/address/data/address_repository.dart',
    'lib/features/business/data/business_repository.dart',
    'lib/features/orders/data/orders_repository.dart',
    'lib/features/orders/data/cart.dart',
    'lib/features/messages/data/messages_repository.dart',
    'lib/features/notifications/data/notifications_repository.dart',
    'lib/features/feed/data/feed_repository.dart',
    'lib/features/services/data/service_profile_repository.dart',
    'lib/features/discovery/discovery_repository.dart',
    'lib/features/home/data/doc_reminder.dart',
    'lib/features/home/data/profile_congrats.dart',
  ];

  /// Providers in those files that legitimately hold no user data.
  const exempt = {
    'homeRepository', 'profileRepository', 'addressRepository', 'businessRepository',
    'ordersRepository', 'messagesRepository', 'notificationsRepository', 'feedRepository',
    'serviceProfileRepository', 'discoveryRepository', 'cartStorage',
    // Admin-curated master lists — same for everyone.
    'professionMaster', 'educationDegrees', 'schoolMaster', 'collegeMaster', 'hobbyMaster',
  };

  final declaration = RegExp(r'^final (\w+)Provider =', multiLine: true);

  test('every user-scoped provider is bound to the signed-in account', () {
    final unbound = <String>[];

    for (final path in userScopedFiles) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is listed here but does not exist');
      final source = file.readAsStringSync();

      for (final match in declaration.allMatches(source)) {
        final name = match.group(1)!;
        if (exempt.contains(name)) continue;

        // The body runs from this declaration to the next one (or end of file).
        final start = match.start;
        final next = declaration.allMatches(source).where((m) => m.start > start);
        final end = next.isEmpty ? source.length : next.first.start;
        final body = source.substring(start, end);

        // A NotifierProvider's state lives in its class, so fall back to the whole file.
        final bound = body.contains('bindToAccount()') ||
            body.contains('authScopeProvider') ||
            (body.contains('NotifierProvider') &&
                (source.contains('bindToAccount()') || source.contains('authScopeProvider')));

        if (!bound) unbound.add('${name}Provider  ($path)');
      }
    }

    expect(
      unbound,
      isEmpty,
      reason: 'These providers cache user data but are not account-bound, so they will serve '
          'the previous account after a logout. Add `ref.bindToAccount();` as the first line '
          'of the provider body (or watch authScopeProvider if it should be reloaded rather '
          'than reset):\n  ${unbound.join('\n  ')}',
    );
  });

  test('the auth controller no longer keeps a hand-maintained invalidate list', () {
    final source = File('lib/features/auth/application/auth_controller.dart').readAsStringSync();
    expect(
      source.contains('_invalidateUserScopedProviders'),
      isFalse,
      reason: 'Cache invalidation is driven by authScopeProvider now. A second, manual list '
          'is what drifted out of date and caused the original leak.',
    );
    expect(source.contains('authScopeProvider'), isTrue);
  });

  test('per-account persisted flags are keyed by user id', () {
    for (final path in ['lib/features/home/data/doc_reminder.dart', 'lib/features/home/data/profile_congrats.dart']) {
      final source = File(path).readAsStringSync();
      expect(
        RegExp(r"'ll_\w+_\$userId'").hasMatch(source),
        isTrue,
        reason: '$path must key its flag by user id — a global key carries the flag across '
            'accounts on a shared device.',
      );
    }
  });
}
