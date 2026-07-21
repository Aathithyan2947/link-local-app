/// An in-app notification (order updates, booking requests, payments, messages…).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    this.body,
    required this.type,
    this.entityType,
    this.entityId,
    required this.isRead,
    this.createdAt,
  });

  final int id;
  final String title;
  final String? body;
  final String type; // order_update | enquiry | payment | message | ...
  final String? entityType; // order | ...
  final int? entityId;
  final bool isRead;
  final DateTime? createdAt;

  /// Booking requests to an SP are actionable (Accept/Reject).
  bool get isBookingRequest => type == 'enquiry' && entityType == 'order';

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        body: body,
        type: type,
        entityType: entityType,
        entityId: entityId,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as int,
        title: j['title'] as String? ?? '',
        body: j['body'] as String?,
        type: j['notificationType'] as String? ?? 'order_update',
        entityType: j['entityType'] as String?,
        entityId: j['entityId'] is int ? j['entityId'] as int : int.tryParse('${j['entityId']}'),
        isRead: (j['isRead'] as bool?) ?? false,
        createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'] as String) : null,
      );
}
