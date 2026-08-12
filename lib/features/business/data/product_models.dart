int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
double? _asDouble(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// One customization an SP offers on a product — replaces the two hard-coded "Eggless" /
/// "Custom message" checkboxes, which only ever suited a bakery. SPs define their own now.
class ProductCustomization {
  const ProductCustomization({
    required this.label,
    this.inputType = 'toggle',
    this.isRequired = false,
  });

  final String label;

  /// `toggle` → a yes/no option. `text` → a toggle plus a free-text box the resident fills in
  /// (what "Custom message" used to be).
  final String inputType;
  final bool isRequired;

  bool get wantsText => inputType == 'text';

  Map<String, dynamic> toJson() => {
        'label': label,
        'inputType': inputType,
        'isRequired': isRequired,
      };

  factory ProductCustomization.fromJson(Map<String, dynamic> j) => ProductCustomization(
        label: j['label'] as String? ?? '',
        inputType: j['inputType'] as String? ?? 'toggle',
        isRequired: j['isRequired'] as bool? ?? false,
      );
}

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
    this.customizations = const [],
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
  /// Free-text note. Superseded by [customizations] for what the resident can pick, but kept
  /// because existing products still carry text here.
  final String? customizationNotes;
  final List<ProductCustomization> customizations;
  final bool isAvailable;

  bool get hasCustomizations => customizations.isNotEmpty;

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
        customizations: ((j['customizations'] as List?) ?? const [])
            .map((e) => ProductCustomization.fromJson(e as Map<String, dynamic>))
            .toList(),
        isAvailable: j['isAvailable'] as bool? ?? true,
      );
}
