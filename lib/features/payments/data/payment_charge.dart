import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../discovery/discovery_repository.dart';
import '../../orders/data/orders_repository.dart';

/// What the payment screens charge: given the chosen method (and UPI app, if any), makes the
/// charge and completes, or throws when it fails. Lets one payment flow serve orders, paid
/// groups and paid events alike.
typedef PaymentCharge = Future<void> Function(WidgetRef ref, String method, String? subMethod);

/// Pays an order's amount due.
PaymentCharge orderCharge(int orderId) =>
    (ref, method, subMethod) =>
        ref.read(ordersRepositoryProvider).pay(orderId, paymentMethod: method, paymentSubMethod: subMethod);

/// Pays a paid group's joining fee; the backend makes the user a member only once it succeeds.
PaymentCharge groupCharge(int groupId) =>
    (ref, _, _) => ref.read(discoveryRepositoryProvider).payForGroup(groupId);

/// Pays a paid event's fee; the backend adds the attendee only once it succeeds.
PaymentCharge eventCharge(int eventId) =>
    (ref, _, _) => ref.read(discoveryRepositoryProvider).payForEvent(eventId);
