int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

class HomeCity {
  const HomeCity({required this.name, this.state});
  final String name;
  final String? state;
  factory HomeCity.fromJson(Map<String, dynamic> j) =>
      HomeCity(name: j['name'] as String? ?? '', state: j['state'] as String?);
  String get label => state == null ? name : '$name, $state';
}

class HomeStats {
  const HomeStats({required this.members, required this.serviceProviders, required this.events});
  final int members;
  final int serviceProviders;
  final int events;
  factory HomeStats.fromJson(Map<String, dynamic> j) => HomeStats(
        members: _asInt(j['members']),
        serviceProviders: _asInt(j['serviceProviders']),
        events: _asInt(j['events']),
      );
}

class ReferralInfo {
  const ReferralInfo({required this.message, required this.balance, required this.pointsPerReferral});
  final String message;
  final int balance;
  final int pointsPerReferral;
  factory ReferralInfo.fromJson(Map<String, dynamic> j) => ReferralInfo(
        message: j['message'] as String? ?? '',
        balance: _asInt(j['balance']),
        pointsPerReferral: _asInt(j['pointsPerReferral']),
      );
}

class DiscussionItem {
  const DiscussionItem({
    required this.id,
    required this.text,
    required this.authorName,
    this.authorPhoto,
    required this.likes,
    required this.comments,
  });
  final int id;
  final String text;
  final String authorName;
  final String? authorPhoto;
  final int likes;
  final int comments;

  factory DiscussionItem.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>?;
    final profile = user?['profile'] as Map<String, dynamic>?;
    final count = j['_count'] as Map<String, dynamic>?;
    return DiscussionItem(
      id: _asInt(j['id']),
      text: j['textContent'] as String? ?? '',
      authorName: profile?['name'] as String? ?? 'Neighbour',
      authorPhoto: profile?['photoUrl'] as String?,
      likes: _asInt(count?['likes']),
      comments: _asInt(count?['comments']),
    );
  }
}

class GroupItem {
  const GroupItem({required this.id, required this.title, required this.members, this.photoUrl});
  final int id;
  final String title;
  final int members;
  final String? photoUrl;
  factory GroupItem.fromJson(Map<String, dynamic> j) {
    final count = j['_count'] as Map<String, dynamic>?;
    return GroupItem(
      id: _asInt(j['id']),
      title: j['title'] as String? ?? '',
      members: _asInt(count?['members']),
      photoUrl: j['photoUrl'] as String?,
    );
  }
}

class WorkshopItem {
  const WorkshopItem({
    required this.id,
    required this.title,
    required this.date,
    required this.attendees,
    this.isPaid = false,
    this.location,
  });
  final int id;
  final String title;
  final DateTime? date;
  final int attendees;
  final bool isPaid;
  final String? location;

  factory WorkshopItem.fromJson(Map<String, dynamic> j) {
    final count = j['_count'] as Map<String, dynamic>?;
    return WorkshopItem(
      id: _asInt(j['id']),
      title: j['title'] as String? ?? '',
      date: j['date'] != null ? DateTime.tryParse(j['date'] as String) : null,
      attendees: _asInt(count?['attendees']),
      isPaid: j['isPaid'] as bool? ?? false,
      location: j['location'] as String?,
    );
  }
}

class ServiceProviderItem {
  const ServiceProviderItem({
    required this.id,
    required this.name,
    this.photoUrl,
    this.service,
    required this.ratingCount,
  });
  final int id;
  final String name;
  final String? photoUrl;
  final String? service;
  final int ratingCount;

  factory ServiceProviderItem.fromJson(Map<String, dynamic> j) {
    final serviceTypes = (j['serviceTypes'] as List?) ?? [];
    String? service;
    if (serviceTypes.isNotEmpty) {
      service = serviceTypes.first['subcategory']?['name'] as String?;
    }
    final count = j['_count'] as Map<String, dynamic>?;
    return ServiceProviderItem(
      id: _asInt(j['id']),
      name: j['name'] as String? ?? '',
      photoUrl: j['photoUrl'] as String?,
      service: service,
      ratingCount: _asInt(count?['ratings']),
    );
  }
}

class Section<T> {
  const Section({required this.total, required this.items});
  final int total;
  final List<T> items;
}

class HomeFeed {
  const HomeFeed({
    this.city,
    required this.stats,
    required this.referral,
    required this.discussions,
    required this.groups,
    required this.workshops,
    required this.serviceProviders,
  });

  final HomeCity? city;
  final HomeStats stats;
  final ReferralInfo referral;
  final List<DiscussionItem> discussions;
  final Section<GroupItem> groups;
  final Section<WorkshopItem> workshops;
  final Section<ServiceProviderItem> serviceProviders;

  factory HomeFeed.fromJson(Map<String, dynamic> j) {
    Section<R> section<R>(String key, R Function(Map<String, dynamic>) fromJson) {
      final s = j[key] as Map<String, dynamic>?;
      final items = ((s?['items'] as List?) ?? [])
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();
      return Section<R>(total: _asInt(s?['total']), items: items);
    }

    return HomeFeed(
      city: j['city'] != null ? HomeCity.fromJson(j['city'] as Map<String, dynamic>) : null,
      stats: HomeStats.fromJson((j['stats'] as Map<String, dynamic>?) ?? {}),
      referral: ReferralInfo.fromJson((j['referral'] as Map<String, dynamic>?) ?? {}),
      discussions: ((j['discussions'] as List?) ?? [])
          .map((e) => DiscussionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      groups: section('groups', GroupItem.fromJson),
      workshops: section('workshops', WorkshopItem.fromJson),
      serviceProviders: section('serviceProviders', ServiceProviderItem.fromJson),
    );
  }
}
