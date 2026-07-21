// Service-SP charges (per session / monthly / hourly). Residents pick one when booking.

const rateTypeLabels = <String, String>{
  'per_session': 'Per session',
  'monthly': 'Monthly',
  'hourly': 'Hourly',
};

/// One published rate for a service SP.
class SpRate {
  const SpRate({required this.rateType, required this.amount, this.id});
  final int? id;
  final String rateType; // per_session | monthly | hourly
  final double amount;

  String get typeLabel => rateTypeLabels[rateType] ?? rateType;

  factory SpRate.fromJson(Map<String, dynamic> j) => SpRate(
        id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}'),
        rateType: j['rateType'] as String? ?? 'per_session',
        amount: j['amount'] is num ? (j['amount'] as num).toDouble() : double.tryParse('${j['amount']}') ?? 0,
      );

  Map<String, dynamic> toJson() => {'rateType': rateType, 'amount': amount};
}
