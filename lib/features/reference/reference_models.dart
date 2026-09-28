import 'dart:math' as math;

class City {
  const City({
    required this.id,
    required this.name,
    this.state,
    this.centerLat,
    this.centerLng,
    this.radiusKm,
  });
  final int id;
  final String name;
  final String? state;

  /// Service area: addresses must fall within [radiusKm] of this centre. All
  /// null when an admin has not set one, and the city is matched by name instead.
  final double? centerLat;
  final double? centerLng;
  final double? radiusKm;

  factory City.fromJson(Map<String, dynamic> j) => City(
        id: j['id'] as int,
        name: j['name'] as String,
        state: j['state'] as String?,
        centerLat: _decimal(j['centerLat']),
        centerLng: _decimal(j['centerLng']),
        radiusKm: _decimal(j['radiusKm']),
      );

  /// The backend sends Prisma decimals as strings.
  static double? _decimal(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  String get label => state == null ? name : '$name, $state';

  bool get hasArea => centerLat != null && centerLng != null && radiusKm != null;

  /// Kilometres from the area's centre, or null without an area.
  double? distanceFromCenterKm(double lat, double lng) =>
      hasArea ? distanceKm(centerLat!, centerLng!, lat, lng) : null;

  /// Whether a point is in the service area; null when there is no area to judge by.
  bool? contains(double lat, double lng) {
    final d = distanceFromCenterKm(lat, lng);
    return d == null ? null : d <= radiusKm!;
  }

  // Cities come from one list, so identity is the id — lets a re-fetched list
  // still match the selected city (e.g. in the dropdown).
  @override
  bool operator ==(Object other) => other is City && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Great-circle distance in kilometres.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * 6371 * math.asin(math.sqrt(a));
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
