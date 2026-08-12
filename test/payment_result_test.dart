@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the contract the payment flow silently broke: each screen must forward its outcome
/// to its caller with `pop(result)`.
///
/// It previously unwound with `popUntil` on a shared route name, which cannot carry a value.
/// The cart screen awaited `push<bool>` and got `null`, so a paid order never cleared the
/// cart, never refreshed My Orders, and never showed the confirmation.
void main() {
  const paymentScreens = [
    'lib/features/payments/presentation/payment_success_screen.dart',
    'lib/features/payments/presentation/payment_failed_screen.dart',
    'lib/features/payments/presentation/payment_upi_screen.dart',
    'lib/features/payments/presentation/payment_method_screen.dart',
  ];

  test('no payment screen unwinds with the old route-name popUntil', () {
    for (final path in paymentScreens) {
      final source = File(path).readAsStringSync();
      expect(source.contains('kPaymentFlowRoute'), isFalse,
          reason: '$path still uses the route-name tag, which cannot return a result');
      // Matches a call, not a mention of the word in a comment.
      expect(RegExp(r'\.popUntil\(').hasMatch(source), isFalse,
          reason: '$path unwinds with popUntil, so its caller never learns the outcome');
    }
  });

  test('the success screen reports success to its caller', () {
    final source = File(paymentScreens[0]).readAsStringSync();
    expect(source.contains('pop(true)'), isTrue);
  });

  test('cancelling a failed payment reports failure, so the cart survives', () {
    final source = File(paymentScreens[1]).readAsStringSync();
    expect(source.contains('pop(false)'), isTrue);
  });

  test('the intermediate screens forward the result upward', () {
    for (final path in [paymentScreens[2], paymentScreens[3]]) {
      final source = File(path).readAsStringSync();
      expect(source.contains('push<bool>'), isTrue,
          reason: '$path must await the outcome of the screen it opens');
      expect(RegExp(r'Navigator\.of\(context\)\.pop\(').hasMatch(source), isTrue,
          reason: '$path must pass that outcome on to its own caller');
    }
  });

  test('a paid cart is cleared and lands on the seller profile', () {
    final source = File('lib/features/orders/presentation/cart_review_screen.dart').readAsStringSync();
    expect(source.contains('if (paid == true)'), isTrue);
    // Captured before clear() — the cart is the only place the seller is recorded.
    expect(
      source.indexOf('final spProfileId = cart.spProfileId;') < source.indexOf('cartProvider.notifier).clear()'),
      isTrue,
      reason: 'the seller must be read before the cart is cleared, or it is lost',
    );
    expect(source.contains('spProfileId: spProfileId'), isTrue);
  });
}
