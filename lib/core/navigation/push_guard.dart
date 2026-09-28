import 'package:flutter/widgets.dart';

extension GuardedNavigation on BuildContext {
  /// Pushes [route], unless the screen this context belongs to is no longer the top route.
  ///
  /// A second tap on a row, card or menu item while its page is still sliding in would
  /// otherwise push another copy of that page. The first push puts the new page on top at
  /// once, so the source screen stops being current and every further tap is ignored — no
  /// timer, so it never swallows a genuine later tap however slow the transition.
  ///
  /// Use this instead of `Navigator.of(context).push` (a test enforces it). Pushing from a
  /// sheet or dialog works as before: its own context is the top route, and a page context
  /// is current again as soon as the sheet has been popped.
  Future<T?> pushPage<T extends Object?>(Route<T> route) {
    final here = ModalRoute.of(this);
    if (here != null && !here.isCurrent) return Future<T?>.value();
    return Navigator.of(this).push(route);
  }
}
