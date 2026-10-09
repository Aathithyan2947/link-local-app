import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_scope.dart';

/// Blocks and unblocks made in this session, by user id. Screens show this over what the
/// server last said, so a block takes effect the moment it's confirmed instead of after a slow
/// profile reload — and an older reload still in flight can't flip it back. Cleared when the
/// account changes.
class BlockOverrides extends Notifier<Map<int, bool>> {
  @override
  Map<int, bool> build() {
    ref.bindToAccount();
    return const {};
  }

  void set(int userId, bool blocked) => state = {...state, userId: blocked};
}

final blockOverridesProvider = NotifierProvider<BlockOverrides, Map<int, bool>>(BlockOverrides.new);

/// Whether the member has blocked [userId]: this session's choice if any, else [fromServer].
bool isBlockedNow(WidgetRef ref, int userId, {required bool fromServer}) =>
    ref.watch(blockOverridesProvider)[userId] ?? fromServer;
