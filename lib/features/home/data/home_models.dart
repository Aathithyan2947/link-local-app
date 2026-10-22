import '../../../core/time/server_time.dart';
import '../../feed/data/post_models.dart';

int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
double? _asDouble(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

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
    this.liked = false,
    this.shares = 0,
    this.createdAt,
    this.canInteract = true,
    this.groupId,
    this.groupTitle,
    this.topComment,
  });
  final int id;
  final String text;
  final String authorName;
  final String? authorPhoto;
  final int likes;
  final int comments;
  final int shares;
  /// Whether the viewer has liked it.
  final bool liked;
  final DateTime? createdAt;
  /// False for a group post the viewer can't join in on (not a member): read-only.
  final bool canInteract;
  /// Set when the post belongs to a group.
  final int? groupId;
  final String? groupTitle;
  /// The most-liked (then newest) comment, previewed on the card.
  final PostComment? topComment;

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
      shares: _asInt(count?['shares']),
      liked: j['viewerLiked'] as bool? ?? false,
      createdAt: parseServerTime(j['createdAt']),
      canInteract: j['canInteract'] as bool? ?? true,
      groupId: (j['group'] as Map<String, dynamic>?)?['id'] != null
          ? _asInt((j['group'] as Map<String, dynamic>)['id'])
          : null,
      groupTitle: (j['group'] as Map<String, dynamic>?)?['title'] as String?,
      topComment: j['topComment'] != null
          ? PostComment.fromJson(j['topComment'] as Map<String, dynamic>)
          : null,
    );
  }
}

class GroupItem {
  const GroupItem({
    required this.id,
    required this.title,
    required this.members,
    this.photoUrl,
    this.ownerName,
    this.creatorId,
    this.isPaid = false,
    this.price,
    this.needsApproval = false,
  });
  final int id;
  final String title;
  final int members;
  final String? photoUrl;
  final String? ownerName;
  final int? creatorId;
  /// Joining a paid group goes through payment; one that [needsApproval] waits for the admin.
  final bool isPaid;
  final double? price;
  final bool needsApproval;
  factory GroupItem.fromJson(Map<String, dynamic> j) {
    final count = j['_count'] as Map<String, dynamic>?;
    final creator = j['creator'] as Map<String, dynamic>?;
    final profile = creator?['profile'] as Map<String, dynamic>?;
    return GroupItem(
      id: _asInt(j['id']),
      title: j['title'] as String? ?? '',
      members: _asInt(count?['members']),
      photoUrl: j['photoUrl'] as String?,
      ownerName: profile?['name'] as String?,
      creatorId: creator?['id'] != null ? _asInt(creator!['id']) : null,
      isPaid: j['isPaid'] == true,
      price: _asDouble(j['price']),
      needsApproval: j['adminApprovalNeeded'] == true,
    );
  }
}

/// How long after it's created an event counts as new.
const kNewEventDays = 7;

/// The "New" badge on an event: created in the last [kNewEventDays] days and not started yet.
/// (Not "has no ratings" — a past event is never new.)
bool isNewEvent({required DateTime? createdAt, required bool hasStarted, DateTime? now}) =>
    createdAt != null &&
    !hasStarted &&
    (now ?? DateTime.now()).difference(createdAt) < const Duration(days: kNewEventDays);

class WorkshopItem {
  const WorkshopItem({
    required this.id,
    required this.title,
    required this.date,
    required this.attendees,
    this.isPaid = false,
    this.location,
    this.startTime,
    this.durationMinutes,
    this.photoUrl,
    this.creatorName,
    this.ratingAvg,
    this.creatorId,
    this.myStatus,
    this.isHost = false,
    this.serverHasStarted,
    this.serverHasEnded,
    this.createdAt,
  });
  final int id;
  final String title;
  final DateTime? date;
  final int attendees;
  final bool isPaid;
  final String? location;
  final DateTime? startTime;
  final int? durationMinutes;
  final String? photoUrl;
  final String? creatorName;
  final double? ratingAvg;
  final int? creatorId;

  /// The viewer's attendance: joined | pending_approval | null.
  final String? myStatus;

  /// The viewer created this event.
  final bool isHost;

  /// From the backend, which owns the rule (an event closes when it starts, in India time).
  final bool? serverHasStarted;

  /// From the backend: the event is over (start + duration, or the end of its day).
  final bool? serverHasEnded;

  /// When the event was created (an instant, so local time).
  final DateTime? createdAt;

  /// Shows the "New" badge — see [isNewEvent].
  bool get isNew => isNewEvent(createdAt: createdAt, hasStarted: hasStarted);

  /// Whether the event has started — closed for joining. Falls back to the device clock
  /// only for a response that predates the backend field.
  bool get hasStarted {
    final fromServer = serverHasStarted;
    if (fromServer != null) return fromServer;
    final d = date;
    if (d == null) return false;
    final t = startTime;
    return DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0).isBefore(DateTime.now());
  }

  /// Whether the event is over — My Events moves it to Past, marked Closed (BUG-101/102).
  /// Falls back to the device clock only for a response that predates the backend field:
  /// start + duration, or the end of the event's day.
  bool get hasEnded {
    final fromServer = serverHasEnded;
    if (fromServer != null) return fromServer;
    final d = date;
    if (d == null) return false;
    final t = startTime;
    final minutes = durationMinutes;
    final end = t != null && minutes != null
        ? DateTime(d.year, d.month, d.day, t.hour, t.minute).add(Duration(minutes: minutes))
        : DateTime(d.year, d.month, d.day + 1);
    return !end.isAfter(DateTime.now());
  }

  /// Started but not over yet.
  bool get isOngoing => hasStarted && !hasEnded;

  /// What a card's action shows, most specific first.
  EventAction get action {
    if (isHost) return EventAction.hosting;
    if (myStatus == 'joined') return EventAction.joined;
    if (myStatus == 'pending_approval') return EventAction.pending;
    if (hasStarted) return EventAction.closed;
    return EventAction.join;
  }

  factory WorkshopItem.fromJson(Map<String, dynamic> j) {
    final count = j['_count'] as Map<String, dynamic>?;
    final creator = j['creator'] as Map<String, dynamic>?;
    final profile = creator?['profile'] as Map<String, dynamic>?;
    return WorkshopItem(
      id: _asInt(j['id']),
      title: j['title'] as String? ?? '',
      // Calendar values (a day and a clock time), not instants: kept as sent — unlike
      // timestamps, which go through parseServerTime.
      date: j['date'] != null ? DateTime.tryParse(j['date'] as String) : null,
      attendees: _asInt(count?['attendees']),
      isPaid: j['isPaid'] as bool? ?? false,
      location: j['location'] as String?,
      startTime: j['startTime'] != null ? DateTime.tryParse(j['startTime'] as String) : null,
      durationMinutes: j['durationMinutes'] != null ? _asInt(j['durationMinutes']) : null,
      photoUrl: j['photoUrl'] as String?,
      creatorName: profile?['name'] as String?,
      ratingAvg: _asDouble(j['ratingAvg']),
      creatorId: creator?['id'] != null ? _asInt(creator!['id']) : null,
      myStatus: j['myStatus'] as String?,
      isHost: j['isHost'] as bool? ?? false,
      serverHasStarted: j['hasStarted'] as bool?,
      serverHasEnded: j['hasEnded'] as bool?,
      createdAt: parseServerTime(j['createdAt']),
    );
  }
}

/// The one action an event card offers the viewer.
enum EventAction { hosting, joined, pending, closed, join }

class ServiceProviderItem {
  const ServiceProviderItem({
    required this.id,
    required this.name,
    this.photoUrl,
    this.service,
    this.services = const [],
    required this.ratingCount,
    this.ratingAvg,
    this.areaName,
    this.cityName,
    this.distanceLabel,
  });
  final int id;
  final String name;
  final String? photoUrl;
  final String? service; // primary service (shown on the card)
  final List<String> services; // every service subcategory (used for search)
  final int ratingCount;
  final double? ratingAvg;

  /// The provider's own area and city — never their street or building.
  final String? areaName;
  final String? cityName;

  /// Rounded distance from the viewer ("< 500 m", "1.5 km", "10+ km"); null when unknown.
  final String? distanceLabel;

  /// "Pai Nagar, Mumbai | 1.5 km", dropping whichever parts are missing; empty when none.
  String get locationLine {
    final place = [areaName, cityName].where((s) => s != null && s.trim().isNotEmpty).join(', ');
    return [place, distanceLabel ?? ''].where((s) => s.isNotEmpty).join(' | ');
  }

  /// Lower-cased haystack for search: provider name + every service/subcategory.
  String get searchText => '$name ${services.join(' ')}'.toLowerCase();

  factory ServiceProviderItem.fromJson(Map<String, dynamic> j) {
    final serviceTypes = (j['serviceTypes'] as List?) ?? [];
    final services = serviceTypes
        .map((e) => (e as Map<String, dynamic>)['subcategory']?['name'] as String?)
        .whereType<String>()
        .toList();
    final count = j['_count'] as Map<String, dynamic>?;
    return ServiceProviderItem(
      id: _asInt(j['id']),
      name: j['name'] as String? ?? '',
      photoUrl: j['photoUrl'] as String?,
      service: services.isNotEmpty ? services.first : null,
      services: services,
      ratingCount: _asInt(count?['ratings']),
      ratingAvg: _asDouble(j['ratingAvg']),
      areaName: j['areaName'] as String?,
      cityName: j['cityName'] as String?,
      distanceLabel: j['distanceLabel'] as String?,
    );
  }
}

/// One service-type shortcut above the provider list, with how many providers in scope
/// offer it — the badge in the Figma design. Counted server-side across the whole scope,
/// not from the page of providers the feed happened to return.
class ServiceCount {
  const ServiceCount({required this.name, required this.count, this.category});
  final String name;
  final int count;
  final String? category;
  factory ServiceCount.fromJson(Map<String, dynamic> j) => ServiceCount(
        name: j['name'] as String? ?? '',
        count: _asInt(j['count']),
        category: j['category'] as String?,
      );
}

/// Result counts for each My Society/Lane/Area/City chip, shown as a badge on the chip.
class ScopeCounts {
  const ScopeCounts({this.society = 0, this.lane = 0, this.area = 0, this.city = 0});
  final int society;
  final int lane;
  final int area;
  final int city;

  /// Looks a count up by the same scope string the chips and API use.
  int? of(String scope) => switch (scope) {
        'society' => society,
        'lane' => lane,
        'area' => area,
        'city' => city,
        _ => null,
      };

  factory ScopeCounts.fromJson(Map<String, dynamic> j) => ScopeCounts(
        society: _asInt(j['society']),
        lane: _asInt(j['lane']),
        area: _asInt(j['area']),
        city: _asInt(j['city']),
      );
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
    this.spServices = const [],
    this.scopeCounts,
    this.scopeLabel,
  });

  final HomeCity? city;
  /// The place every section is filtered by — the picked area, or the member's society /
  /// lane / area / city per the chip — exactly as the backend applied it (with its fallbacks
  /// when a society or lane isn't filled in). Null against an older backend.
  final String? scopeLabel;
  final HomeStats stats;
  final ReferralInfo referral;
  final List<DiscussionItem> discussions;
  final Section<GroupItem> groups;
  final Section<WorkshopItem> workshops;
  final Section<ServiceProviderItem> serviceProviders;
  final List<ServiceCount> spServices;
  /// Null against a backend that predates scope counts — the chips then render without
  /// badges rather than claiming every scope holds zero results.
  final ScopeCounts? scopeCounts;

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
      spServices: (((j['serviceProviders'] as Map<String, dynamic>?)?['services'] as List?) ?? [])
          .map((e) => ServiceCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      scopeCounts: j['scopeCounts'] == null
          ? null
          : ScopeCounts.fromJson(j['scopeCounts'] as Map<String, dynamic>),
      scopeLabel: j['scopeLabel'] as String?,
    );
  }
}
