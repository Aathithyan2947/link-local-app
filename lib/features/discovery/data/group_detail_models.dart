import '../../home/data/home_models.dart';

int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
double? _asDouble(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// One joined member, for the Members action on the group profile.
class GroupMember {
  const GroupMember({required this.userId, required this.name, this.photoUrl, this.isCreator = false});
  final int userId;
  final String name;
  final String? photoUrl;
  final bool isCreator;

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
        userId: _asInt(j['userId']),
        name: j['name'] as String? ?? 'Member',
        photoUrl: j['photoUrl'] as String?,
        isCreator: j['isCreator'] as bool? ?? false,
      );
}

/// Full interest-group detail backing the Group Profile screen.
class GroupDetail {
  const GroupDetail({
    required this.id,
    required this.title,
    this.description,
    this.photoUrl,
    required this.creatorName,
    this.createdAt,
    required this.membersCount,
    this.isPaid = false,
    this.price,
    this.ratingAvg,
    required this.ratingCount,
    this.discussions = const [],
    this.myStatus,
    this.myPaymentStatus,
    this.isCreator = false,
    this.isPrivate = false,
    this.maxMembers,
    this.adminApprovalNeeded = false,
    this.area,
    this.isMuted = false,
  });

  final int id;
  final String title;
  final String? description;
  final String? photoUrl;
  final String creatorName;
  final DateTime? createdAt;
  final int membersCount;
  final bool isPaid;
  final double? price;
  final double? ratingAvg;
  final int ratingCount;
  final List<DiscussionItem> discussions;
  final String? myStatus; // joined | pending_approval | exited | null
  final String? myPaymentStatus; // paid | unpaid | null
  final bool isCreator;
  final bool isPrivate;
  final int? maxMembers;
  final bool adminApprovalNeeded;
  /// Where the group is anchored — the creator's area. Names the discussions header.
  final String? area;
  final bool isMuted;

  bool get isMember => isCreator || myStatus == 'joined';
  bool get isPending => myStatus == 'pending_approval';
  bool get needsPayment => isPaid && myStatus == 'joined' && myPaymentStatus != 'paid';

  factory GroupDetail.fromJson(Map<String, dynamic> j) {
    final count = j['_count'] as Map<String, dynamic>?;
    final creatorProfile = (j['creator'] as Map<String, dynamic>?)?['profile'] as Map<String, dynamic>?;
    final mine = j['myMembership'] as Map<String, dynamic>?;
    return GroupDetail(
      id: _asInt(j['id']),
      title: j['title'] as String? ?? '',
      description: j['description'] as String?,
      photoUrl: j['photoUrl'] as String?,
      creatorName: creatorProfile?['name'] as String? ?? 'Owner',
      createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'] as String) : null,
      membersCount: _asInt(count?['members']),
      isPaid: j['isPaid'] as bool? ?? false,
      price: _asDouble(j['price']),
      ratingAvg: _asDouble(j['ratingAvg']),
      ratingCount: _asInt(j['ratingCount']),
      discussions: ((j['discussions'] as List?) ?? [])
          .map((e) => DiscussionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      myStatus: mine?['status'] as String?,
      myPaymentStatus: mine?['paymentStatus'] as String?,
      isCreator: j['isCreator'] as bool? ?? false,
      isPrivate: j['isPrivate'] as bool? ?? false,
      maxMembers: j['maxMembers'] != null ? _asInt(j['maxMembers']) : null,
      adminApprovalNeeded: j['adminApprovalNeeded'] as bool? ?? false,
      area: j['area'] as String?,
      isMuted: mine?['muted'] as bool? ?? false,
    );
  }
}
