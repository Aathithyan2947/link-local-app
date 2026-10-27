import '../../../core/time/server_time.dart';

int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
double _asDouble(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

/// "₹500", or "₹499.50" when there are paise: an advance split can leave them.
String inr(double v) => '₹${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

/// One line item within an order.
class OrderLine {
  const OrderLine({
    required this.productName,
    this.productPhoto,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.customizationNotes,
  });
  final String productName;
  final String? productPhoto;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final String? customizationNotes;

  factory OrderLine.fromJson(Map<String, dynamic> j) {
    final p = j['product'] as Map<String, dynamic>?;
    return OrderLine(
      productName: p?['name'] as String? ?? 'Item',
      productPhoto: p?['photoUrl'] as String?,
      quantity: _asDouble(j['quantity']),
      unitPrice: _asDouble(j['unitPrice']),
      totalPrice: _asDouble(j['totalPrice']),
      customizationNotes: j['customizationNotes'] as String?,
    );
  }
}

/// Fee breakdown returned by POST /orders/quote (drives the cart totals + coupon preview).
class OrderQuote {
  const OrderQuote({
    required this.subtotal,
    required this.deliveryCharge,
    required this.packagingCharge,
    required this.platformFee,
    required this.discount,
    required this.total,
    this.freeDeliveryThreshold,
    this.freeDeliveryRemaining = 0,
    this.advancePercent = 100,
    double? advanceAmount,
    this.payLater = false,
  }) : advanceAmount = advanceAmount ?? total;
  final double subtotal;
  final double deliveryCharge;
  final double packagingCharge;
  final double platformFee;
  final double discount;
  final double total;
  final double? freeDeliveryThreshold;
  final double freeDeliveryRemaining;

  /// The provider's advance terms (BUG-097): the share of [total] paid at checkout (100 is
  /// everything), that amount, and whether nothing is paid now ("No Advance").
  final double advancePercent;
  final double advanceAmount;
  final bool payLater;

  /// Something is left to pay after checkout.
  bool get hasBalance => total - advanceAmount > 0.005;

  factory OrderQuote.fromJson(Map<String, dynamic> j) => OrderQuote(
        subtotal: _asDouble(j['subtotal']),
        deliveryCharge: _asDouble(j['deliveryCharge']),
        packagingCharge: _asDouble(j['packagingCharge']),
        platformFee: _asDouble(j['platformFee']),
        discount: _asDouble(j['discount']),
        total: _asDouble(j['total']),
        freeDeliveryThreshold: j['freeDeliveryThreshold'] != null ? _asDouble(j['freeDeliveryThreshold']) : null,
        freeDeliveryRemaining: _asDouble(j['freeDeliveryRemaining']),
        advancePercent: j['advancePercent'] != null ? _asDouble(j['advancePercent']) : 100,
        advanceAmount: j['advanceAmount'] != null ? _asDouble(j['advanceAmount']) : null,
        payLater: j['payLater'] as bool? ?? false,
      );
}

/// Human labels for product-order statuses.
const orderStatusLabels = <String, String>{
  'placed': 'New',
  'confirmed': 'Confirmed',
  'in_progress': 'In progress',
  'delivered': 'Delivered',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
  'rejected': 'Declined',
};

/// Human labels for service-booking statuses.
const bookingStatusLabels = <String, String>{
  'requested': 'Requested',
  'accepted': 'Accepted',
  'confirmed': 'Confirmed',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
  'rejected': 'Declined',
};

const rateTypeLabels = <String, String>{
  'per_session': 'Per session',
  'monthly': 'Monthly',
  'hourly': 'Hourly',
};

/// A date-anchored time slot attached to an order/booking.
class OrderSlot {
  const OrderSlot({required this.date, required this.startTime, required this.endTime});
  final String date;
  final String startTime; // "HH:MM" (from @db.Time → we read the time portion)
  final String endTime;
  factory OrderSlot.fromJson(Map<String, dynamic> j) {
    String hm(dynamic v) {
      final s = '$v';
      // @db.Time serialises as an ISO datetime; take HH:MM.
      final t = s.contains('T') ? s.split('T')[1] : s;
      return t.length >= 5 ? t.substring(0, 5) : t;
    }
    return OrderSlot(
      date: ('${j['slotDate']}').split('T')[0],
      startTime: hm(j['startTime']),
      endTime: hm(j['endTime']),
    );
  }
}

/// One recorded charge attempt on an order (mock gateway — see `backend/src/lib/payments.ts`).
class OrderPaymentModel {
  const OrderPaymentModel({
    required this.amount,
    required this.paymentMethod,
    this.paymentSubMethod,
    required this.paymentStatus,
    this.paidAt,
    this.createdAt,
  });
  final double amount;
  final String paymentMethod;
  final String? paymentSubMethod; // e.g. "GPay" — brand-level detail within paymentMethod
  final String paymentStatus; // paid | failed | refunded
  final DateTime? paidAt;
  final DateTime? createdAt;

  factory OrderPaymentModel.fromJson(Map<String, dynamic> j) => OrderPaymentModel(
        amount: _asDouble(j['amount']),
        paymentMethod: j['paymentMethod'] as String? ?? '',
        paymentSubMethod: j['paymentSubMethod'] as String?,
        paymentStatus: j['paymentStatus'] as String? ?? '',
        paidAt: parseServerTime(j['paidAt']),
        createdAt: parseServerTime(j['createdAt']),
      );
}

class OrderModel {
  const OrderModel({
    required this.id,
    required this.orderKind,
    required this.status,
    this.deliveryType,
    required this.subtotal,
    required this.deliveryCharge,
    required this.packagingCharge,
    required this.platformFee,
    required this.discountApplied,
    required this.totalAmount,
    required this.amountDue,
    this.rateType,
    this.rateAmount,
    this.specialInstructions,
    this.deliveryTimeWindow,
    this.placedAt,
    this.slot,
    required this.buyerName,
    this.buyerPhoto,
    this.buyerId,
    this.deliveryAddress,
    required this.spProfileId,
    required this.spName,
    this.spPhoto,
    required this.spUserId,
    this.items = const [],
    this.paid = false,
    this.payments = const [],
    this.amountPaid = 0,
    double? balanceDue,
    this.advancePercent = 100,
    this.payLater = false,
  }) : balanceDue = balanceDue ?? (paid ? 0 : totalAmount);

  final int id;
  final String orderKind; // product | booking
  final String status;
  final String? deliveryType;
  final double subtotal;
  final double deliveryCharge;
  final double packagingCharge;
  final double platformFee;
  final double discountApplied;
  final double totalAmount;
  /// What the next payment charges (BUG-097): the advance at checkout when the provider asks
  /// for one, then whatever is left (see backend `paymentSummary`).
  final double amountDue;

  /// Paid so far, and still owed.
  final double amountPaid;
  final double balanceDue;

  /// The share of the total charged at checkout: 100 is everything, 0 is nothing.
  final double advancePercent;

  /// "No Advance": placed without paying, then paid from Order Tracking.
  final bool payLater;

  /// Something has been paid and something is still owed (an advance order's balance).
  bool get hasBalance => paid && balanceDue > 0.005;

  /// Nothing more to pay.
  bool get fullyPaid => paid && balanceDue <= 0.005;
  final String? rateType;
  final double? rateAmount;
  final String? specialInstructions;
  final String? deliveryTimeWindow;
  final DateTime? placedAt;
  final OrderSlot? slot;
  final String buyerName;
  final String? buyerPhoto;
  final int? buyerId;
  final String? deliveryAddress;
  final int spProfileId;
  final String spName;
  final String? spPhoto;
  final int spUserId;
  final List<OrderLine> items;
  final bool paid;
  final List<OrderPaymentModel> payments;

  bool get isBooking => orderKind == 'booking';

  /// The same order at a new [status] — for showing a status change at once, before the
  /// server's copy comes back.
  OrderModel withStatus(String status) => OrderModel(
        id: id,
        orderKind: orderKind,
        status: status,
        deliveryType: deliveryType,
        subtotal: subtotal,
        deliveryCharge: deliveryCharge,
        packagingCharge: packagingCharge,
        platformFee: platformFee,
        discountApplied: discountApplied,
        totalAmount: totalAmount,
        amountDue: amountDue,
        rateType: rateType,
        rateAmount: rateAmount,
        specialInstructions: specialInstructions,
        deliveryTimeWindow: deliveryTimeWindow,
        placedAt: placedAt,
        slot: slot,
        buyerName: buyerName,
        buyerPhoto: buyerPhoto,
        buyerId: buyerId,
        deliveryAddress: deliveryAddress,
        spProfileId: spProfileId,
        spName: spName,
        spPhoto: spPhoto,
        spUserId: spUserId,
        items: items,
        paid: paid,
        payments: payments,
        amountPaid: amountPaid,
        balanceDue: balanceDue,
        advancePercent: advancePercent,
        payLater: payLater,
      );

  String get statusLabel =>
      (isBooking ? bookingStatusLabels : orderStatusLabels)[status] ?? status;
  bool get isHomeDelivery => deliveryType == 'home_delivery';
  String? get rateTypeLabel => rateType == null ? null : rateTypeLabels[rateType] ?? rateType;

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    final buyer = j['buyer'] as Map<String, dynamic>?;
    final buyerProfile = buyer?['profile'] as Map<String, dynamic>?;
    final sp = j['spProfile'] as Map<String, dynamic>?;
    final payments = (j['payments'] as List?) ?? [];
    final slot = j['scheduledSlot'] as Map<String, dynamic>?;
    final paidPayments = payments.where((p) => (p as Map)['paymentStatus'] == 'paid');
    final paidSum = paidPayments.fold<double>(0, (s, p) => s + _asDouble((p as Map)['amount']));
    return OrderModel(
      id: _asInt(j['id']),
      orderKind: j['orderKind'] as String? ?? 'product',
      status: j['status'] as String? ?? 'placed',
      deliveryType: j['deliveryType'] as String?,
      subtotal: _asDouble(j['subtotal']),
      deliveryCharge: _asDouble(j['deliveryCharge']),
      packagingCharge: _asDouble(j['packagingCharge']),
      platformFee: _asDouble(j['platformFee']),
      discountApplied: _asDouble(j['discountApplied']),
      totalAmount: _asDouble(j['totalAmount']),
      amountDue: _asDouble(j['amountDue'] ?? j['totalAmount']),
      rateType: j['rateType'] as String?,
      rateAmount: j['rateAmount'] != null ? _asDouble(j['rateAmount']) : null,
      specialInstructions: j['specialInstructions'] as String?,
      deliveryTimeWindow: j['deliveryTimeWindow'] as String?,
      placedAt: parseServerTime(j['placedAt']),
      slot: slot != null ? OrderSlot.fromJson(slot) : null,
      buyerName: buyerProfile?['name'] as String? ?? 'Customer',
      buyerPhoto: buyerProfile?['photoUrl'] as String?,
      buyerId: buyer?['id'] != null ? _asInt(buyer!['id']) : null,
      deliveryAddress: (j['deliveryAddress'] as Map<String, dynamic>?)?['fullAddress'] as String?,
      spProfileId: _asInt(sp?['id']),
      spName: sp?['name'] as String? ?? 'Seller',
      spPhoto: sp?['photoUrl'] as String?,
      spUserId: _asInt(sp?['userId']),
      items: ((j['items'] as List?) ?? []).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)).toList(),
      paid: paidPayments.isNotEmpty,
      payments: payments.map((p) => OrderPaymentModel.fromJson(p as Map<String, dynamic>)).toList(),
      // An older backend sends none of these: one payment settled the order.
      amountPaid: j['amountPaid'] != null ? _asDouble(j['amountPaid']) : paidSum,
      balanceDue: j['balanceDue'] != null ? _asDouble(j['balanceDue']) : null,
      advancePercent: j['advancePercent'] != null ? _asDouble(j['advancePercent']) : 100,
      payLater: j['payLater'] as bool? ?? false,
    );
  }
}
