import '../../home/data/home_models.dart';

int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
DateTime? _asDate(dynamic v) => v == null ? null : DateTime.tryParse('$v');

/// Events the current user hosts vs. has joined — `GET /events/mine`.
class MyEvents {
  const MyEvents({required this.hosted, required this.attending});
  final List<WorkshopItem> hosted;
  final List<WorkshopItem> attending;

  factory MyEvents.fromJson(Map<String, dynamic> j) => MyEvents(
        hosted: ((j['hosted'] as List?) ?? []).map((e) => WorkshopItem.fromJson(e as Map<String, dynamic>)).toList(),
        attending:
            ((j['attending'] as List?) ?? []).map((e) => WorkshopItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Groups the current user owns vs. has joined — `GET /groups/mine`.
class MyGroups {
  const MyGroups({required this.owned, required this.joined});
  final List<GroupItem> owned;
  final List<GroupItem> joined;

  factory MyGroups.fromJson(Map<String, dynamic> j) => MyGroups(
        owned: ((j['owned'] as List?) ?? []).map((e) => GroupItem.fromJson(e as Map<String, dynamic>)).toList(),
        joined: ((j['joined'] as List?) ?? []).map((e) => GroupItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// One review the current user submitted, with the reviewed entity's display info folded in.
/// [role]/[address] are only ever set for service-provider reviews; [subtitle] carries the
/// "By `host`" / "Admin: `owner`" line for events/groups.
class SubmittedReview {
  const SubmittedReview({
    required this.entityId,
    required this.name,
    this.photoUrl,
    this.subtitle,
    this.role,
    this.address,
    required this.rating,
    this.review,
    this.createdAt,
  });
  final int entityId;
  final String name;
  final String? photoUrl;
  final String? subtitle;
  final String? role;
  final String? address;
  final int rating;
  final String? review;
  final DateTime? createdAt;
}

/// Every review the current user has submitted, across the three reviewable entities —
/// `GET /reviews/mine`.
class MyReviews {
  const MyReviews({required this.serviceProviders, required this.events, required this.groups});
  final List<SubmittedReview> serviceProviders;
  final List<SubmittedReview> events;
  final List<SubmittedReview> groups;

  factory MyReviews.fromJson(Map<String, dynamic> j) {
    final serviceProviders = ((j['serviceProviders'] as List?) ?? []).map((e) {
      final m = e as Map<String, dynamic>;
      final profile = m['profile'] as Map<String, dynamic>?;
      final serviceTypes = (profile?['serviceTypes'] as List?) ?? [];
      final String? role = serviceTypes.isNotEmpty
          ? ((serviceTypes.first as Map<String, dynamic>)['subcategory']?['name'] as String?)
          : null;
      return SubmittedReview(
        entityId: _asInt(profile?['id']),
        name: profile?['name'] as String? ?? 'Service Provider',
        photoUrl: profile?['photoUrl'] as String?,
        role: role,
        address: (profile?['address'] as Map<String, dynamic>?)?['fullAddress'] as String?,
        rating: _asInt(m['rating']),
        review: m['review'] as String?,
        createdAt: _asDate(m['createdAt']),
      );
    }).toList();

    final events = ((j['events'] as List?) ?? []).map((e) {
      final m = e as Map<String, dynamic>;
      final event = m['event'] as Map<String, dynamic>?;
      final hostName =
          ((event?['creator'] as Map<String, dynamic>?)?['profile'] as Map<String, dynamic>?)?['name'] as String?;
      return SubmittedReview(
        entityId: _asInt(event?['id']),
        name: event?['title'] as String? ?? 'Event',
        photoUrl: event?['photoUrl'] as String?,
        subtitle: hostName != null ? 'By $hostName' : null,
        rating: _asInt(m['rating']),
        review: m['review'] as String?,
        createdAt: _asDate(m['createdAt']),
      );
    }).toList();

    final groups = ((j['groups'] as List?) ?? []).map((e) {
      final m = e as Map<String, dynamic>;
      final group = m['group'] as Map<String, dynamic>?;
      final ownerName =
          ((group?['creator'] as Map<String, dynamic>?)?['profile'] as Map<String, dynamic>?)?['name'] as String?;
      return SubmittedReview(
        entityId: _asInt(group?['id']),
        name: group?['title'] as String? ?? 'Group',
        photoUrl: group?['photoUrl'] as String?,
        subtitle: ownerName != null ? 'Admin: $ownerName' : null,
        rating: _asInt(m['rating']),
        review: m['review'] as String?,
        createdAt: _asDate(m['createdAt']),
      );
    }).toList();

    return MyReviews(serviceProviders: serviceProviders, events: events, groups: groups);
  }
}
