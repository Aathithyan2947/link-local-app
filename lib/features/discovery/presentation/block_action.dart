import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../../core/theme/app_colors.dart';
import '../../messages/data/messages_repository.dart';
import '../data/block_overrides.dart';
import '../discovery_repository.dart';

/// Blocks or unblocks [userId] — the one flow behind every Block / Unblock button.
///
/// Blocking asks first. The screen switches as soon as it's confirmed (see
/// [blockOverridesProvider]); the request runs behind it and, if it fails, the switch is undone
/// with a message. Their chat, the conversation list and anything in [refresh] reload in the
/// background, so nothing waits on them.
///
/// The container is taken up front: the dialog and request span awaits during which the
/// widget that started this can be rebuilt or closed.
Future<void> setBlocked(
  BuildContext context, {
  required int userId,
  required String name,
  required bool block,
  List<ProviderOrFamily> refresh = const [],
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  if (block) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block $name?'),
        content: const Text("You won't be able to message or call each other."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }

  final overrides = container.read(blockOverridesProvider.notifier);
  final before = container.read(blockOverridesProvider)[userId];
  overrides.set(userId, block);
  messenger.showSnackBar(SnackBar(content: Text(block ? 'Blocked' : 'Unblocked')));

  final repo = container.read(discoveryRepositoryProvider);
  try {
    block ? await repo.blockUser(userId) : await repo.unblockUser(userId);
  } catch (_) {
    before == null ? overrides.set(userId, !block) : overrides.set(userId, before);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Could not ${block ? 'block' : 'unblock'} $name. Try again.')));
    return;
  }
  container
    ..invalidate(threadProvider(userId))
    ..invalidate(conversationsProvider);
  for (final p in refresh) {
    container.invalidate(p);
  }
}
