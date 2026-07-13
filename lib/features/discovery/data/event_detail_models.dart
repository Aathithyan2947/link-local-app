int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
double? _asDouble(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// A review left on an event.
class EventReview {
  const EventReview({required this.raterName, required this.raterType, required this.rating, this.review});
  final String raterName;
  final String raterType;
  final int rating;
  final String? review;

  String get raterTypeLabel => switch (raterType) {
        'service_provider' => 'Service Provider',
        'business_listing' => 'Business',
        _ => 'Resident',
      };

  factory EventReview.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>?;
    final profile = user?['profile'] as Map<String, dynamic>?;
    return EventReview(
      raterName: profile?['name'] as String? ?? 'Member',
      raterType: user?['userType'] as String? ?? 'resident',
      rating: _asInt(j['rating']),
      review: j['review'] as String?,
    );
  }
}

/// The event's host (creator profile summary).
class EventHost {
  const EventHost({required this.name, this.photoUrl, this.aboutMe, this.service, this.location});
  final String name;
  final String? photoUrl;
  final String? aboutMe;
  final String? service;
  final String? location;

  factory EventHost.fromJson(Map<String, dynamic>? creator) {
    final profile = creator?['profile'] as Map<String, dynamic>?;
    final serviceTypes = (profile?['serviceTypes'] as List?) ?? [];
    final service = serviceTypes.isNotEmpty
        ? (serviceTypes.first['subcategory']?['name'] as String?)
        : null;
    final area = (profile?['address'] as Map<String, dynamic>?)?['area'] as Map<String, dynamic>?;
    final city = area?['city'] as Map<String, dynamic>?;
    final parts = <String>[
      if ((area?['areaName'] as String?)?.isNotEmpty == true) area!['areaName'] as String,
      if ((city?['name'] as String?)?.isNotEmpty == true) city!['name'] as String,
    ];
    return EventHost(
      name: profile?['name'] as String? ?? 'Host',
      photoUrl: profile?['photoUrl'] as String?,
      aboutMe: profile?['aboutMe'] as String?,
      service: service,
      location: parts.isEmpty ? null : parts.join(', '),
    );
  }
}

/// Full event detail backing the Workshop-details screen.
class EventDetail {
  const EventDetail({
    required this.id,
    required this.title,
    this.description,
    this.photoUrl,
    this.date,
    this.startTime,
    this.durationMinutes,
    required this.mode,
    this.location,
    this.onlineLink,
    this.isPaid = false,
    this.price,
    this.maxAttendees,
    required this.attendeesCount,
    this.ratingAvg,
    required this.ratingCount,
    this.rawMaterials = const [],
    this.reviews = const [],
    required this.host,
    this.myStatus,
    this.myPaymentStatus,
  });

  final int id;
  final String title;
  final String? description;
  final String? photoUrl;
  final DateTime? date;
  final DateTime? startTime;
  final int? durationMinutes;
  final String mode;
  final String? location;
  final String? onlineLink;
  final bool isPaid;
  final double? price;
  final int? maxAttendees;
  final int attendeesCount;
  final double? ratingAvg;
  final int ratingCount;
  final List<String> rawMaterials;
  final List<EventReview> reviews;
  final EventHost host;
  final String? myStatus; // joined | withdrawn | pending_approval | null
  final String? myPaymentStatus; // paid | unpaid | null

  bool get isJoined => myStatus == 'joined';
  bool get needsPayment => isPaid && isJoined && myPaymentStatus != 'paid';

  factory EventDetail.fromJson(Map<String, dynamic> j) {
    final count = j['_count'] as Map<String, dynamic>?;
    final mine = j['myAttendance'] as Map<String, dynamic>?;
    return EventDetail(
      id: _asInt(j['id']),
      title: j['title'] as String? ?? '',
      description: j['description'] as String?,
      photoUrl: j['photoUrl'] as String?,
      date: j['date'] != null ? DateTime.tryParse(j['date'] as String) : null,
      startTime: j['startTime'] != null ? DateTime.tryParse(j['startTime'] as String) : null,
      durationMinutes: j['durationMinutes'] != null ? _asInt(j['durationMinutes']) : null,
      mode: j['mode'] as String? ?? 'offline',
      location: j['location'] as String?,
      onlineLink: j['onlineLink'] as String?,
      isPaid: j['isPaid'] as bool? ?? false,
      price: _asDouble(j['price']),
      maxAttendees: j['maxAttendees'] != null ? _asInt(j['maxAttendees']) : null,
      attendeesCount: _asInt(count?['attendees']),
      ratingAvg: _asDouble(j['ratingAvg']),
      ratingCount: _asInt(j['ratingCount']),
      rawMaterials: ((j['rawMaterials'] as List?) ?? [])
          .map((e) => (e as Map<String, dynamic>)['material'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      reviews: ((j['ratings'] as List?) ?? [])
          .map((e) => EventReview.fromJson(e as Map<String, dynamic>))
          .toList(),
      host: EventHost.fromJson(j['creator'] as Map<String, dynamic>?),
      myStatus: mine?['status'] as String?,
      myPaymentStatus: mine?['paymentStatus'] as String?,
    );
  }
}
