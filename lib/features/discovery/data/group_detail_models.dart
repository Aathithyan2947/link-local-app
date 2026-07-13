import '../../home/data/home_models.dart';

int _asInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
double? _asDouble(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

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
    );
  }
}
