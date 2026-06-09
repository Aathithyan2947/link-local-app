/// A complex/building suggestion from the seeded directory.
class ComplexSuggestion {
  const ComplexSuggestion({
    required this.apartment,
    this.lane1,
    required this.locality,
    required this.cityId,
    this.pincode,
    required this.city,
  });
  final String apartment;
  final String? lane1;
  final String locality;
  final int cityId;
  final String? pincode;
  final String city;

  factory ComplexSuggestion.fromJson(Map<String, dynamic> j) => ComplexSuggestion(
        apartment: j['apartment'] as String,
        lane1: j['lane1'] as String?,
        locality: j['locality'] as String? ?? '',
        cityId: j['cityId'] as int,
        pincode: j['pincode'] as String?,
        city: j['city'] as String? ?? '',
      );
}

/// A locality (area) suggestion from the seeded directory.
class LocalitySuggestion {
  const LocalitySuggestion({
    required this.areaId,
    required this.cityId,
    required this.areaName,
    this.suburb,
    this.pincode,
    required this.city,
  });
  final int areaId;
  final int cityId;
  final String areaName;
  final String? suburb;
  final String? pincode;
  final String city;

  factory LocalitySuggestion.fromJson(Map<String, dynamic> j) => LocalitySuggestion(
        areaId: j['areaId'] as int,
        cityId: j['cityId'] as int,
        areaName: j['areaName'] as String,
        suburb: j['suburb'] as String?,
        pincode: j['pincode'] as String?,
        city: j['city'] as String? ?? '',
      );
}

class DirectoryResults {
  const DirectoryResults({required this.localities, required this.complexes});
  final List<LocalitySuggestion> localities;
  final List<ComplexSuggestion> complexes;
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
