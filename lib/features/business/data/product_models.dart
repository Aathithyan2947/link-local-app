int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
double? _asDouble(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// A service provider's product / menu item (sp_products).
class SpProduct {
  const SpProduct({
    required this.id,
    required this.name,
    this.description,
    this.price,
    this.unit,
    this.quantityMetric,
    this.category,
    this.photoUrl,
    this.customizationNotes,
    this.isAvailable = true,
  });

  final int id;
  final String name;
  final String? description;
  final double? price;
  final String? unit;
  final String? quantityMetric;
  final String? category;
  final String? photoUrl;
  final String? customizationNotes;
  final bool isAvailable;

  /// e.g. `500g` or `per piece`.
  String get quantityLabel => quantityMetric?.isNotEmpty == true ? quantityMetric! : (unit ?? '');

  factory SpProduct.fromJson(Map<String, dynamic> j) => SpProduct(
        id: _asInt(j['id']),
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        price: _asDouble(j['price']),
        unit: j['unit'] as String?,
        quantityMetric: j['quantityMetric'] as String?,
        category: j['category'] as String?,
        photoUrl: j['photoUrl'] as String?,
        customizationNotes: j['customizationNotes'] as String?,
        isAvailable: j['isAvailable'] as bool? ?? true,
      );
}
