class BlockedUserItem {
  const BlockedUserItem({
    required this.userId,
    required this.name,
    this.photoUrl,
    required this.role,
    this.location,
  });

  final int userId;
  final String name;
  final String? photoUrl;
  final String role;
  final String? location;

  factory BlockedUserItem.fromJson(Map<String, dynamic> j) => BlockedUserItem(
        userId: j['userId'] is int ? j['userId'] as int : int.tryParse('${j['userId']}') ?? 0,
        name: j['name'] as String? ?? 'Unknown',
        photoUrl: j['photoUrl'] as String?,
        role: j['role'] as String? ?? 'Resident',
        location: j['location'] as String?,
      );
}
