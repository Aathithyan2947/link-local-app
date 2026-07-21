int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
double _asDouble(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

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
  });
  final double subtotal;
  final double deliveryCharge;
  final double packagingCharge;
  final double platformFee;
  final double discount;
  final double total;
  final double? freeDeliveryThreshold;
  final double freeDeliveryRemaining;

  factory OrderQuote.fromJson(Map<String, dynamic> j) => OrderQuote(
        subtotal: _asDouble(j['subtotal']),
        deliveryCharge: _asDouble(j['deliveryCharge']),
        packagingCharge: _asDouble(j['packagingCharge']),
        platformFee: _asDouble(j['platformFee']),
        discount: _asDouble(j['discount']),
        total: _asDouble(j['total']),
        freeDeliveryThreshold: j['freeDeliveryThreshold'] != null ? _asDouble(j['freeDeliveryThreshold']) : null,
        freeDeliveryRemaining: _asDouble(j['freeDeliveryRemaining']),
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
    this.rateType,
    this.rateAmount,
    this.specialInstructions,
    this.placedAt,
    this.slot,
    required this.buyerName,
    this.buyerPhoto,
    required this.spProfileId,
    required this.spName,
    this.spPhoto,
    required this.spUserId,
    this.items = const [],
    this.paid = false,
  });

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
  final String? rateType;
  final double? rateAmount;
  final String? specialInstructions;
  final DateTime? placedAt;
  final OrderSlot? slot;
  final String buyerName;
  final String? buyerPhoto;
  final int spProfileId;
  final String spName;
  final String? spPhoto;
  final int spUserId;
  final List<OrderLine> items;
  final bool paid;

  bool get isBooking => orderKind == 'booking';
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
      rateType: j['rateType'] as String?,
      rateAmount: j['rateAmount'] != null ? _asDouble(j['rateAmount']) : null,
      specialInstructions: j['specialInstructions'] as String?,
      placedAt: j['placedAt'] != null ? DateTime.tryParse(j['placedAt'] as String) : null,
      slot: slot != null ? OrderSlot.fromJson(slot) : null,
      buyerName: buyerProfile?['name'] as String? ?? 'Customer',
      buyerPhoto: buyerProfile?['photoUrl'] as String?,
      spProfileId: _asInt(sp?['id']),
      spName: sp?['name'] as String? ?? 'Seller',
      spPhoto: sp?['photoUrl'] as String?,
      spUserId: _asInt(sp?['userId']),
      items: ((j['items'] as List?) ?? []).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)).toList(),
      paid: payments.any((p) => (p as Map)['paymentStatus'] == 'paid'),
    );
  }
}
