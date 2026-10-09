import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_scope.dart';
import '../../auth/application/auth_controller.dart';
import '../../messages/data/message_models.dart';
import '../../messages/data/messages_repository.dart';
import 'order_models.dart';
import 'orders_repository.dart';

/// Profile → Transaction History shows what needs attention, like an unread badge: payments
/// that arrived since Payments was last opened, orders still in progress, and unread messages.
/// A 0 shows no pill.

/// Statuses an order ends in; anything else is still in progress.
const finishedOrderStatuses = {'completed', 'cancelled', 'rejected'};

/// When a payment happened (paid, else created) — the moment it counts as new from.
DateTime? paymentTime(OrderPaymentModel p) => p.paidAt ?? p.createdAt;

/// Payments made or received (every row the Transactions screen lists) after [seenAt].
int newPaymentCount(List<OrderModel> mine, List<OrderModel> received, DateTime seenAt) => [
  for (final o in [...mine, ...received])
    for (final p in o.payments)
      if (paymentTime(p)?.isAfter(seenAt) ?? false) p,
].length;

/// Orders placed plus (for an SP) orders received that haven't finished, each order once.
int inProgressOrderCount(List<OrderModel> mine, List<OrderModel> received) => {
  for (final o in [...mine, ...received])
    if (!finishedOrderStatuses.contains(o.status)) o.id,
}.length;

/// Unread messages across all conversations (the same total as Home's chat badge).
int unreadMessageCount(List<Conversation> conversations) => conversations.fold(0, (sum, c) => sum + c.unread);

/// When this account last opened Payments, as stored on the server, so opening Payments on one
/// device clears the count on all of them. Null until loaded, or if loading failed (then no
/// count is shown rather than a wrong one). Tied to the account: logging out drops it.
///
/// Auto-disposed, so it's re-read each time the profile opens and picks up a visit to
/// Payments made on another device.
class PaymentsSeenAt extends AsyncNotifier<DateTime> {
  @override
  Future<DateTime> build() {
    ref.bindToAccount();
    return ref.watch(ordersRepositoryProvider).paymentsSeenAt();
  }

  /// Payments was opened. If the server can't be reached the count simply stays until the
  /// next visit.
  Future<void> markSeen() async {
    try {
      state = AsyncData(await ref.read(ordersRepositoryProvider).markPaymentsSeen());
    } catch (_) {}
  }
}

final paymentsSeenAtProvider = AsyncNotifierProvider.autoDispose<PaymentsSeenAt, DateTime>(PaymentsSeenAt.new);

/// The member's own orders and (SP only) the orders they received, or null until both have
/// loaded. A failed load also gives null, so no count is shown rather than a wrong one.
(List<OrderModel>, List<OrderModel>)? _orders(Ref ref) {
  final isSp = ref.watch(authControllerProvider).user?.isServiceProvider ?? false;
  final mine = ref.watch(myOrdersProvider).asData?.value;
  final received = isSp ? ref.watch(incomingOrdersProvider).asData?.value : const <OrderModel>[];
  if (mine == null || received == null) return null;
  return (mine, received);
}

/// Profile → Transaction History → Payments: payments new since Payments was last opened.
final paymentsCountProvider = Provider.autoDispose<int?>((ref) {
  final o = _orders(ref);
  final seenAt = ref.watch(paymentsSeenAtProvider).asData?.value;
  return o == null || seenAt == null ? null : newPaymentCount(o.$1, o.$2, seenAt);
});

/// Profile → Transaction History → Order History: orders still in progress.
final ordersCountProvider = Provider.autoDispose<int?>((ref) {
  final o = _orders(ref);
  return o == null ? null : inProgressOrderCount(o.$1, o.$2);
});

/// Profile → Transaction History → Messages: unread messages.
final conversationsCountProvider = Provider.autoDispose<int?>((ref) {
  final conversations = ref.watch(conversationsProvider).asData?.value;
  return conversations == null ? null : unreadMessageCount(conversations);
});
