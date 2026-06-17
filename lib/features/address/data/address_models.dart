/// A curated locality from the Address Master — powers both the autocomplete directory and
/// the 2 km nearby-autofill. Holds lane/area/suburb/city only (never building/flat).
class MasterSuggestion {
  const MasterSuggestion({
    this.masterId,
    required this.cityId,
    this.complex,
    this.lane1,
    this.lane2,
    this.area,
    this.suburb,
    this.pincode,
    this.latitude,
    this.longitude,
    required this.city,
    this.state,
    this.distanceKm,
  });
  final int? masterId;
  final int cityId;
  final String? complex; // building / complex name (search suggestions only)
  final String? lane1;
  final String? lane2;
  final String? area;
  final String? suburb;
  final String? pincode;
  final double? latitude;
  final double? longitude;
  final String city;
  final String? state;
  final double? distanceKm;

  factory MasterSuggestion.fromJson(Map<String, dynamic> j) => MasterSuggestion(
        masterId: j['masterId'] as int?,
        cityId: j['cityId'] as int,
        complex: j['complex'] as String?,
        lane1: j['lane1'] as String?,
        lane2: j['lane2'] as String?,
        area: j['area'] as String?,
        suburb: j['suburb'] as String?,
        pincode: j['pincode'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        city: j['city'] as String? ?? '',
        state: j['state'] as String?,
        distanceKm: (j['distanceKm'] as num?)?.toDouble(),
      );

  /// Primary label for a suggestion row: the building/complex name when present,
  /// otherwise the lane line, falling back to area/suburb.
  String get title {
    if (complex != null && complex!.isNotEmpty) return complex!;
    final lanes = [lane1, lane2].where((e) => e != null && e.isNotEmpty).join(', ');
    if (lanes.isNotEmpty) return lanes;
    return [area, suburb].where((e) => e != null && e.isNotEmpty).join(', ');
  }

  /// Secondary line (lane / area / suburb / city / pincode).
  String get subtitle =>
      [lane1, lane2, area, suburb, city, pincode].where((e) => e != null && e.toString().isNotEmpty).join(', ');
}

class DirectoryResults {
  const DirectoryResults({required this.localities});
  final List<MasterSuggestion> localities;
}

/// Current user's address + address-proof verification status.
class AddressProofInfo {
  const AddressProofInfo({
    required this.hasAddress,
    this.fullAddress,
    this.city,
    required this.status,
  });

  final bool hasAddress;
  final String? fullAddress;
  final String? city;
  final String status; // none | pending | approved | rejected

  bool get hasDoc => status != 'none';
  bool get isVerified => status == 'approved';

  String get statusLabel => switch (status) {
        'approved' => 'Verified',
        'pending' => 'Pending review',
        'rejected' => 'Rejected — re-upload',
        _ => 'Not uploaded',
      };

  factory AddressProofInfo.fromAddressJson(Map<String, dynamic>? a) {
    if (a == null) return const AddressProofInfo(hasAddress: false, status: 'none');
    final docs = ((a['verificationDocs'] as List?) ?? []).cast<Map<String, dynamic>>();
    final statuses = docs.map((d) => d['status'] as String?).whereType<String>().toList();
    final status = statuses.contains('approved')
        ? 'approved'
        : statuses.contains('pending')
            ? 'pending'
            : statuses.contains('rejected')
                ? 'rejected'
                : 'none';
    final area = a['area'] as Map<String, dynamic>?;
    final city = area?['city'] as Map<String, dynamic>?;
    return AddressProofInfo(
      hasAddress: true,
      fullAddress: a['fullAddress'] as String?,
      city: city?['name'] as String?,
      status: status,
    );
  }
}

/// A configurable field in a city's address-capture form (admin-defined).
class CityAddressField {
  const CityAddressField({required this.fieldKey, required this.label, required this.isRequired});
  final String fieldKey;
  final String label;
  final bool isRequired;

  factory CityAddressField.fromJson(Map<String, dynamic> j) => CityAddressField(
        fieldKey: j['fieldKey'] as String,
        label: j['label'] as String,
        isRequired: j['isRequired'] as bool? ?? false,
      );
}

/// A geocoded address from a map pin (reverse geocoding).
class GeoAddress {
  const GeoAddress({
    required this.latitude,
    required this.longitude,
    this.fullAddress,
    this.lane1,
    this.locality,
    this.area,
    this.suburb,
    this.city,
    this.state,
    this.pincode,
  });
  final double latitude;
  final double longitude;
  final String? fullAddress;
  final String? lane1;
  final String? locality;
  final String? area;
  final String? suburb;
  final String? city;
  final String? state;
  final String? pincode;
}
