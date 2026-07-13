import '../../home/data/home_models.dart';
import 'sp_detail_models.dart';

int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

/// A member's public profile — the "User" frame. Reuses the SP-detail
/// sub-models (education/profession/event/group) since the shapes match.
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.userId,
    required this.name,
    this.photoUrl,
    this.aboutMe,
    this.locationLabel,
    required this.userType,
    this.mobile,
    this.servicesContacted = 0,
    this.educations = const [],
    this.professions = const [],
    this.events = const [],
    this.posts = const [],
    this.groups = const [],
  });

  final int id;
  final int userId;
  final String name;
  final String? photoUrl;
  final String? aboutMe;
  final String? locationLabel;
  final String userType;
  final String? mobile;
  final int servicesContacted;
  final List<SpEducation> educations;
  final List<SpProfession> professions;
  final List<SpEvent> events;
  final List<DiscussionItem> posts;
  final List<SpGroup> groups;

  factory PublicProfile.fromJson(Map<String, dynamic> j) {
    final address = j['address'] as Map<String, dynamic>?;
    final area = address?['area'] as Map<String, dynamic>?;
    final city = area?['city'] as Map<String, dynamic>?;
    final locParts = <String>[
      if ((area?['areaName'] as String?)?.isNotEmpty == true) area!['areaName'] as String,
      if ((city?['name'] as String?)?.isNotEmpty == true) city!['name'] as String,
    ];

    List<T> list<T>(String key, T Function(Map<String, dynamic>) fromJson) =>
        ((j[key] as List?) ?? []).map((e) => fromJson(e as Map<String, dynamic>)).toList();

    final user = j['user'] as Map<String, dynamic>?;
    return PublicProfile(
      id: _asInt(j['id']),
      userId: _asInt(user?['id']),
      name: j['name'] as String? ?? '',
      photoUrl: j['photoUrl'] as String?,
      aboutMe: j['aboutMe'] as String?,
      locationLabel: locParts.isEmpty ? null : locParts.join(', '),
      userType: user?['userType'] as String? ?? 'resident',
      mobile: user?['mobile'] as String?,
      servicesContacted: _asInt(j['servicesContacted']),
      educations: list('educations', SpEducation.fromJson),
      professions: list('professions', SpProfession.fromJson),
      events: list('events', SpEvent.fromJson),
      posts: list('posts', DiscussionItem.fromJson),
      groups: list('groups', SpGroup.fromJson),
    );
  }
}
