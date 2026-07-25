import '../../business/data/availability_models.dart';
import '../../business/data/product_models.dart';
import '../../business/data/rate_models.dart';
import '../../home/data/home_models.dart';

int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
double? _asDouble(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// One education entry (degree + institution).
class SpEducation {
  const SpEducation({required this.label, this.institution});
  final String label;
  final String? institution;
  factory SpEducation.fromJson(Map<String, dynamic> j) {
    final degree = j['degree'] as String?;
    final inst = (j['collegeName'] ?? j['schoolName']) as String?;
    return SpEducation(
      label: (degree?.isNotEmpty == true ? degree : inst) ?? 'Education',
      institution: degree?.isNotEmpty == true ? inst : null,
    );
  }
}

/// One profession entry.
class SpProfession {
  const SpProfession({required this.label, this.category});
  final String label;
  final String? category;
  factory SpProfession.fromJson(Map<String, dynamic> j) {
    final detail = j['companyOrDetail'] as String?;
    final cat = (j['professionMaster'] as Map<String, dynamic>?)?['category'] as String?;
    return SpProfession(
      label: (detail?.isNotEmpty == true ? detail : cat) ?? 'Professional',
      category: detail?.isNotEmpty == true ? cat : null,
    );
  }
}

/// A verified review from another member.
class SpReview {
  const SpReview({
    required this.raterName,
    required this.raterType,
    required this.rating,
    this.review,
    this.areaContext,
  });
  final String raterName;
  final String raterType; // resident | service_provider | business_listing
  final int rating;
  final String? review;
  final String? areaContext;

  /// Human label for the reviewer's role.
  String get raterTypeLabel => switch (raterType) {
        'service_provider' => 'Service Provider',
        'business_listing' => 'Business',
        _ => 'Resident',
      };

  factory SpReview.fromJson(Map<String, dynamic> j) {
    final rater = j['rater'] as Map<String, dynamic>?;
    final profile = rater?['profile'] as Map<String, dynamic>?;
    return SpReview(
      raterName: profile?['name'] as String? ?? 'Member',
      raterType: rater?['userType'] as String? ?? 'resident',
      rating: _asInt(j['rating']),
      review: j['review'] as String?,
      areaContext: j['areaContext'] as String?,
    );
  }
}

/// An event the provider hosts or attends.
class SpEvent {
  const SpEvent({required this.event, required this.relation});
  final WorkshopItem event;
  final String relation; // hosting | attending

  bool get isHosting => relation == 'hosting';
  bool get isPast => event.date != null && event.date!.isBefore(DateTime.now());

  factory SpEvent.fromJson(Map<String, dynamic> j) => SpEvent(
        event: WorkshopItem.fromJson(j),
        relation: j['relation'] as String? ?? 'attending',
      );
}

/// An interest group the provider admins or is a member of.
class SpGroup {
  const SpGroup({required this.group, required this.role});
  final GroupItem group;
  final String role; // admin | member
  factory SpGroup.fromJson(Map<String, dynamic> j) => SpGroup(
        group: GroupItem.fromJson(j),
        role: j['role'] as String? ?? 'member',
      );
}

/// Full service-provider profile backing the detail screen.
class ServiceProviderDetail {
  const ServiceProviderDetail({
    required this.id,
    required this.name,
    this.photoUrl,
    this.aboutMe,
    this.yearsOfExperience,
    this.service,
    this.services = const [],
    this.locationLabel,
    this.ratingAvg,
    required this.ratingCount,
    this.willingToTravel = false,
    this.mobile,
    this.userId,
    this.providerKind = 'product',
    this.hasMenu = false,
    this.hasDateBooking = false,
    this.availability,
    this.rates = const [],
    this.educations = const [],
    this.professions = const [],
    this.gallery = const [],
    this.reviews = const [],
    this.events = const [],
    this.posts = const [],
    this.groups = const [],
    this.products = const [],
  });

  final int id;
  final String name;
  final String? photoUrl;
  final String? aboutMe;
  final int? yearsOfExperience;
  final String? service; // primary service subcategory (shown under the name)
  final List<String> services;
  final String? locationLabel;
  final double? ratingAvg;
  final int ratingCount;
  final bool willingToTravel;
  final String? mobile;
  final int? userId;
  final String providerKind; // product (menu/cart) | service (charges/booking)
  final bool hasMenu; // true when any subcategory type == 'menu'
  final bool hasDateBooking; // true when any subcategory type == 'date'
  final SpAvailability? availability;
  final List<SpRate> rates;
  final List<SpEducation> educations;

  bool get isService => !hasMenu;
  final List<SpProfession> professions;
  final List<String> gallery;
  final List<SpReview> reviews;
  final List<SpEvent> events;
  final List<DiscussionItem> posts;
  final List<SpGroup> groups;
  final List<SpProduct> products;

  factory ServiceProviderDetail.fromJson(Map<String, dynamic> j) {
    final serviceTypes = (j['serviceTypes'] as List?) ?? [];
    final services = serviceTypes
        .map((e) => (e as Map<String, dynamic>)['subcategory']?['name'] as String?)
        .whereType<String>()
        .toList();
    // Collect all feature signals: subcategory.type column + onboarding field types
    final featureTypes = <String>{};
    for (final e in serviceTypes) {
      final sub = (e as Map<String, dynamic>)['subcategory'] as Map<String, dynamic>?;
      final t = sub?['type'] as String?;
      if (t != null) featureTypes.add(t);
      final fields = (sub?['fields'] as List?) ?? [];
      for (final f in fields) {
        final ft = (f as Map<String, dynamic>)['fieldType'] as String?;
        if (ft != null) featureTypes.add(ft);
      }
    }

    final address = j['address'] as Map<String, dynamic>?;
    final area = address?['area'] as Map<String, dynamic>?;
    final city = area?['city'] as Map<String, dynamic>?;
    final locParts = <String>[
      if ((area?['areaName'] as String?)?.isNotEmpty == true) area!['areaName'] as String,
      if ((city?['name'] as String?)?.isNotEmpty == true) city!['name'] as String,
    ];

    final gallery = ((j['media'] as List?) ?? [])
        .where((m) {
          final t = (m as Map<String, dynamic>)['mediaType'] as String?;
          return t == 'photo' || t == 'services_card' || t == 'menu_card';
        })
        .map((m) => (m as Map<String, dynamic>)['url'] as String?)
        .whereType<String>()
        .toList();

    final delivery = j['delivery'] as Map<String, dynamic>?;

    List<T> list<T>(String key, T Function(Map<String, dynamic>) fromJson) =>
        ((j[key] as List?) ?? []).map((e) => fromJson(e as Map<String, dynamic>)).toList();

    return ServiceProviderDetail(
      id: _asInt(j['id']),
      name: j['name'] as String? ?? '',
      photoUrl: j['photoUrl'] as String?,
      aboutMe: j['aboutMe'] as String?,
      yearsOfExperience: j['yearsOfExperience'] != null ? _asInt(j['yearsOfExperience']) : null,
      service: services.isNotEmpty ? services.first : null,
      services: services,
      locationLabel: locParts.isEmpty ? null : locParts.join(', '),
      ratingAvg: _asDouble(j['ratingAvg']),
      ratingCount: _asInt(j['ratingCount']),
      willingToTravel: (delivery?['offersHomeDelivery'] as bool?) ??
          (j['availability'] as Map<String, dynamic>?)?['willingToTravel'] as bool? ??
          false,
      mobile: (j['user'] as Map<String, dynamic>?)?['mobile'] as String?,
      userId: (j['user'] as Map<String, dynamic>?)?['id'] != null
          ? _asInt((j['user'] as Map<String, dynamic>)['id'])
          : null,
      providerKind: j['providerKind'] as String? ?? 'service',
      hasMenu: j['hasMenu'] as bool? ?? featureTypes.contains('menu'),
      hasDateBooking: j['hasDateBooking'] as bool? ?? featureTypes.contains('date'),
      availability:
          j['availability'] == null ? null : SpAvailability.fromJson(j['availability'] as Map<String, dynamic>),
      rates: ((j['rates'] as List?) ?? []).map((e) => SpRate.fromJson(e as Map<String, dynamic>)).toList(),
      educations: list('educations', SpEducation.fromJson),
      professions: list('professions', SpProfession.fromJson),
      gallery: gallery,
      reviews: list('ratings', SpReview.fromJson),
      events: list('events', SpEvent.fromJson),
      posts: list('posts', DiscussionItem.fromJson),
      groups: list('groups', SpGroup.fromJson),
      products: list('products', SpProduct.fromJson),
    );
  }
}
