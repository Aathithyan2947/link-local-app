import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/push_guard.dart';
import '../../discovery/presentation/event_detail_screen.dart';
import '../../discovery/presentation/group_profile_screen.dart';
import '../../feed/presentation/post_detail_screen.dart';
import '../../messages/data/messages_repository.dart';
import '../../messages/presentation/chat_screen.dart';
import '../../orders/presentation/order_tracking_screen.dart';
import '../data/notification_models.dart';

/// Whether tapping [n] leads anywhere (otherwise a tap only marks it read).
bool notificationHasTarget(AppNotification n) =>
    n.entityId != null && const {'message', 'order', 'post', 'event', 'group'}.contains(n.entityType);

/// Opens the screen a notification is about, and completes when the user comes back:
///  * message → the chat with the sender (`entityId` is the sender's user id)
///  * order → the order · post → the post (with its comments) · event / group → its page
/// Anything else does nothing.
Future<void> openNotificationTarget(BuildContext context, WidgetRef ref, AppNotification n) async {
  final id = n.entityId;
  if (id == null || !notificationHasTarget(n)) return;

  if (n.entityType == 'message') {
    // The chat header needs the person's name; the thread carries it (and ChatScreen reads the
    // same cached thread, so this is no extra request). Never block opening on it.
    var name = 'Chat';
    String? photo;
    try {
      final thread = await ref.read(threadProvider(id).future);
      name = thread.otherName;
      photo = thread.otherPhoto;
    } catch (_) {}
    if (!context.mounted) return;
    await context.pushPage(MaterialPageRoute(
      builder: (_) => ChatScreen(otherUserId: id, otherName: name, otherPhoto: photo),
    ));
    return;
  }

  final screen = notificationScreen(n);
  if (screen != null) await context.pushPage(MaterialPageRoute(builder: (_) => screen));
}

/// The screen for a non-message notification, or null when it has none.
Widget? notificationScreen(AppNotification n) {
  final id = n.entityId;
  if (id == null) return null;
  return switch (n.entityType) {
    'order' => OrderTrackingScreen(orderId: id),
    'post' => PostDetailScreen(id: id),
    'event' => EventDetailScreen(id: id),
    'group' => GroupProfileScreen(id: id),
    _ => null,
  };
}
