// BUG-027: Groups → a group → Guidelines opens a bottom sheet (drag handle, "Guidelines" title,
// the group's description as a scrollable body that stays clear of the home indicator; "No
// guidelines yet." without one). The header action card (Members · Add Person · Guidelines)
// leaves no empty gap under it, and its tap ripple stays inside the rounded card.
//
// Run: see integration_test/support/harness.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/theme/app_colors.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';

import 'support/harness.dart';

void main() {
  initIntegrationTest();
  final api = TestApi();

  /// Numbered rules up to ~1.9k characters (the create form allows 2000), ending on a line that
  /// only shows once the sheet is scrolled to the bottom.
  const lastRule = 'Last rule: thank the volunteers who sweep the track.';
  final longGuidelines = () {
    final b = StringBuffer();
    for (var i = 1; b.length < 1800; i++) {
      b.write('$i. Be kind, keep posts about walking and share route changes early.\n');
    }
    b.write(lastRule);
    return b.toString();
  }();

  late SeededUser creator;
  late SeededUser viewer;
  late String longTitle;
  late String blankTitle;

  setUpAll(() async {
    final s = uniqueStamp();
    creator = await api.createMember(name: 'Gcreator ${s.letters}', email: 'bug027.creator.${s.digits}@example.com');
    viewer = await api.createMember(name: 'Gviewer ${s.letters}', email: 'bug027.viewer.${s.digits}@example.com');
    longTitle = 'Walkers ${s.letters}';
    blankTitle = 'Readers ${s.letters}';
    await api.createGroup(creator, longTitle, description: longGuidelines);
    final blankId = await api.createGroup(creator, blankTitle);
    // A member of the blank one: members get a Post row under the card instead of Join.
    await api.joinGroup(viewer, blankId);
  });

  /// The white action card under the green header.
  Finder actionCard() => find.ancestor(
        of: find.text('Add Person'),
        matching: find.byWidgetPredicate((w) =>
            w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).boxShadow != null),
      );

  testWidgets('a long description opens in a scrollable sheet that clears the home indicator', (tester) async {
    await launchApp(tester);
    await loginWithEmail(tester, viewer.email, viewer.password);
    await openGroupFromGroupsTab(tester, longTitle);

    // No gap under the action card: a non-member's Join button sits 12px below it.
    final card = tester.getRect(actionCard());
    final join = tester.getRect(find.widgetWithText(ElevatedButton, 'Join Group'));
    expect(join.top - card.bottom, moreOrLessEquals(12, epsilon: 0.5),
        reason: 'only the button\'s own 12px padding between the card and Join (card $card, join $join)');
    // The card still overlaps the green header: green on both sides of its upper part.
    final pixels = await Pixels.of(tester);
    final green = rgbOf(AppColors.primary);
    expect(Pixels.distance(pixels.at(Offset(card.left / 2, card.top + 11)), green), lessThan(6),
        reason: 'the header green runs on behind the card\'s top half');
    expect(Pixels.distance(pixels.at(Offset(card.left / 2, card.bottom - 6)), green), greaterThan(40),
        reason: 'and stops above the card\'s bottom edge');
    await screenshot(tester, 'bug027_group_header_nonmember');

    await tapOn(tester, find.descendant(of: find.byType(GroupProfileScreen), matching: find.text('Guidelines')),
        settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, bottomSheet, reason: 'Guidelines opens a bottom sheet');
    await pumpFor(tester, const Duration(milliseconds: 500));

    final sheet = tester.getRect(bottomSheet);
    final screen = screenSize(tester);
    final insets = viewPadding(tester);
    // Drag handle at the top, then the title, then the description.
    final handle = inSheet(find.byWidgetPredicate(
        (w) => w is Container && w.constraints == const BoxConstraints.tightFor(width: 40, height: 4)));
    expect(handle, findsOneWidget, reason: 'a drag handle');
    expect(tester.getRect(handle).top - sheet.top, lessThan(16));
    expect(tester.getCenter(handle).dx, moreOrLessEquals(sheet.center.dx, epsilon: 1));
    final title = inSheet(find.text('Guidelines'));
    expect(title, findsOneWidget);
    expect(tester.getRect(title).top, greaterThan(tester.getRect(handle).bottom));
    final body = inSheet(find.text(longGuidelines));
    expect(body, findsOneWidget, reason: 'the description is the body');
    expect(sheet.top, greaterThan(insets.top), reason: 'the sheet stays below the status bar');

    // The body scrolls inside the sheet; the title stays put.
    final scrollable = inSheet(find.byType(Scrollable));
    expect(scrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0), reason: 'a long text scrolls');
    final viewport = tester.getRect(scrollable);
    expect(viewport.bottom, lessThanOrEqualTo(screen.height - insets.bottom + 0.5),
        reason: 'nothing under the home indicator (viewport $viewport, screen $screen, insets $insets)');
    await screenshot(tester, 'bug027_guidelines_long_top');

    final titleTop = tester.getRect(title).top;
    for (var i = 0; i < 12 && position.pixels < position.maxScrollExtent; i++) {
      await tester.drag(scrollable, const Offset(0, -500));
      await pumpFor(tester, const Duration(milliseconds: 400));
    }
    await pumpFor(tester, const Duration(milliseconds: 1200)); // iOS bounces past the end, then back
    expect(position.pixels, moreOrLessEquals(position.maxScrollExtent, epsilon: 1), reason: 'scrolls to the end');
    expect(tester.getRect(title).top, titleTop, reason: 'the title stays put while the text scrolls');
    // At the end, the text's last line sits inside the visible viewport, above the home indicator.
    final textBottom = tester.getRect(body).bottom;
    expect(textBottom, lessThanOrEqualTo(viewport.bottom), reason: 'the last rule is visible');
    expect(textBottom, lessThanOrEqualTo(screen.height - insets.bottom));
    expect(tester.takeException(), isNull, reason: 'no overflow');
    await screenshot(tester, 'bug027_guidelines_long_end');

    await dismissSheet(tester);
  });

  testWidgets('no description shows "No guidelines yet." and the card sits flush on a member\'s page',
      (tester) async {
    await launchApp(tester);
    await loginWithEmail(tester, viewer.email, viewer.password);
    await openGroupFromGroupsTab(tester, blankTitle);

    final card = tester.getRect(actionCard());
    final post = tester.getRect(find.ancestor(of: find.text('Post'), matching: find.byType(TextButton)));
    expect(post.top - card.bottom, moreOrLessEquals(12, epsilon: 0.5),
        reason: 'a member\'s Post row is 12px below the card, no gap (card $card, post $post)');
    await screenshot(tester, 'bug027_group_header_member');

    await tapOn(tester, find.descendant(of: find.byType(GroupProfileScreen), matching: find.text('Guidelines')),
        settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, bottomSheet);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(inSheet(find.text('Guidelines')), findsOneWidget);
    expect(inSheet(find.text('No guidelines yet.')), findsOneWidget);
    final screen = screenSize(tester);
    expect(tester.getRect(bottomSheet).height, lessThan(screen.height / 3), reason: 'a short sheet for a short text');
    await screenshot(tester, 'bug027_guidelines_empty');
    await dismissSheet(tester);
  });

  testWidgets('the action ripple stays inside the rounded card', (tester) async {
    await launchApp(tester);
    await loginWithEmail(tester, viewer.email, viewer.password);
    await openGroupFromGroupsTab(tester, longTitle);

    final card = tester.getRect(actionCard());
    // Just outside the 16px rounded corners, and just inside the card next to them.
    final corners = {
      'top-left': card.topLeft + const Offset(2, 2),
      'bottom-left': card.bottomLeft + const Offset(2, -2),
    };
    final insideTile = card.topLeft + const Offset(24, 6);
    final before = await Pixels.of(tester);
    expect(Pixels.distance(before.at(insideTile), [0xFF, 0xFF, 0xFF]), lessThan(4), reason: 'the card is white');

    // Hold a finger on Members (the left action, which owns both left corners) so its ripple
    // and highlight grow over the whole tile.
    final members = find.descendant(of: find.byType(GroupProfileScreen), matching: find.text('1 Member'));
    final gesture = await tester.startGesture(tester.getCenter(members));
    await pumpFor(tester, const Duration(milliseconds: 700));
    final during = await Pixels.of(tester);
    await screenshot(tester, 'bug027_action_ripple_pressed');
    await gesture.cancel(); // lift without tapping (no Members sheet)
    await pumpFor(tester, const Duration(milliseconds: 600));

    expect(Pixels.distance(during.at(insideTile), before.at(insideTile)), greaterThan(3),
        reason: 'the press paints a ripple/highlight inside the tile '
            '(before ${before.at(insideTile)}, during ${during.at(insideTile)})');
    for (final e in corners.entries) {
      expect(Pixels.distance(during.at(e.value), before.at(e.value)), lessThan(3),
          reason: 'outside the ${e.key} rounded corner nothing changes while pressed '
              '(before ${before.at(e.value)}, during ${during.at(e.value)})');
    }
    expect(Pixels.distance(before.at(corners['top-left']!), rgbOf(AppColors.primary)), lessThan(6),
        reason: 'the green shows outside the top-left corner (${before.at(corners['top-left']!)})');
    expect(Pixels.distance(before.at(corners['bottom-left']!), [0xFF, 0xFF, 0xFF]), greaterThan(3),
        reason: 'the page shows outside the bottom-left corner, not the white card '
            '(${before.at(corners['bottom-left']!)})');
  });
}
