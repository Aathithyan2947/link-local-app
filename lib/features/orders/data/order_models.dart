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

/// Human labels + colours for order statuses.
const orderStatusLabels = <String, String>{
  'placed': 'New',
  'confirmed': 'Confirmed',
  'in_progress': 'In progress',
  'delivered': 'Delivered',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
};

class OrderModel {
  const OrderModel({
    required this.id,
    required this.status,
    this.deliveryType,
    required this.subtotal,
    required this.deliveryCharge,
    required this.discountApplied,
    required this.totalAmount,
    this.specialInstructions,
    this.placedAt,
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
  final String status;
  final String? deliveryType;
  final double subtotal;
  final double deliveryCharge;
  final double discountApplied;
  final double totalAmount;
  final String? specialInstructions;
  final DateTime? placedAt;
  final String buyerName;
  final String? buyerPhoto;
  final int spProfileId;
  final String spName;
  final String? spPhoto;
  final int spUserId;
  final List<OrderLine> items;
  final bool paid;

  String get statusLabel => orderStatusLabels[status] ?? status;
  bool get isHomeDelivery => deliveryType == 'home_delivery';

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    final buyer = j['buyer'] as Map<String, dynamic>?;
    final buyerProfile = buyer?['profile'] as Map<String, dynamic>?;
    final sp = j['spProfile'] as Map<String, dynamic>?;
    final payments = (j['payments'] as List?) ?? [];
    return OrderModel(
      id: _asInt(j['id']),
      status: j['status'] as String? ?? 'placed',
      deliveryType: j['deliveryType'] as String?,
      subtotal: _asDouble(j['subtotal']),
      deliveryCharge: _asDouble(j['deliveryCharge']),
      discountApplied: _asDouble(j['discountApplied']),
      totalAmount: _asDouble(j['totalAmount']),
      specialInstructions: j['specialInstructions'] as String?,
      placedAt: j['placedAt'] != null ? DateTime.tryParse(j['placedAt'] as String) : null,
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
