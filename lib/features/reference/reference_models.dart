class City {
  const City({required this.id, required this.name, this.state});
  final int id;
  final String name;
  final String? state;

  factory City.fromJson(Map<String, dynamic> j) =>
      City(id: j['id'] as int, name: j['name'] as String, state: j['state'] as String?);

  String get label => state == null ? name : '$name, $state';
}

class ReferralSource {
  const ReferralSource({required this.id, required this.source, required this.label});
  final int id;
  final String source; // e.g. social_media | friends_family | user_id | event_id | other
  final String label;

  factory ReferralSource.fromJson(Map<String, dynamic> j) => ReferralSource(
        id: j['id'] as int,
        source: j['source'] as String? ?? '',
        label: j['label'] as String? ?? (j['source'] as String? ?? ''),
      );

  /// True for the "Referred by a user" source, which needs a member ID / referral code.
  bool get needsMemberId => source == 'user_id';
}

class ServiceSubcategory {
  const ServiceSubcategory({required this.id, required this.name, required this.categoryId});
  final int id;
  final String name;
  final int categoryId;

  factory ServiceSubcategory.fromJson(Map<String, dynamic> j) => ServiceSubcategory(
        id: j['id'] as int,
        name: j['name'] as String,
        categoryId: j['categoryId'] as int,
      );
}

class ServiceCategory {
  const ServiceCategory({required this.id, required this.name, required this.subcategories});
  final int id;
  final String name;
  final List<ServiceSubcategory> subcategories;

  factory ServiceCategory.fromJson(Map<String, dynamic> j) => ServiceCategory(
        id: j['id'] as int,
        name: j['name'] as String,
        subcategories: ((j['subcategories'] as List?) ?? [])
            .map((e) => ServiceSubcategory.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
