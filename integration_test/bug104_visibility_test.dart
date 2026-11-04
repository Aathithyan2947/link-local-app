// BUG-104 (part 1): Profile visibility. A profile set to "Only me" (or to an area / apartment the
// viewer isn't in) shows "This profile is private" to others, and so does its "View More" posts
// list. The group Members sheet leaves hidden members out and says how many have private
// profiles; the group's creator still sees everyone. Profiles refetch when opened, so a changed
// setting applies on the next open, without restarting the app. (Names on posts and comments
// stay visible: out of scope here.)
//
// Run: see integration_test/support/harness.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/discovery/presentation/user_profile_screen.dart';
import 'package:link_local/features/feed/presentation/user_posts_screen.dart';
import 'package:link_local/features/home/presentation/home_feed_screen.dart';
import 'package:link_local/features/members/presentation/members_screen.dart';

import 'support/harness.dart';

void main() {
  initIntegrationTest();
  final api = TestApi();

  late SeededUser owner; // the member whose profile goes private
  late SeededUser viewer; // same area, another apartment
  late SeededUser creator; // runs the group both are seen in
  late String postText;
  late String groupTitle;
  late int groupId;

  setUpAll(() async {
    final s = uniqueStamp();
    owner = await api.createMember(
        name: 'Vowner ${s.letters}', email: 'bug104.owner.${s.digits}@example.com', apartment: 'Lotus Heights');
    viewer = await api.createMember(
        name: 'Vviewer ${s.letters}', email: 'bug104.viewer.${s.digits}@example.com', apartment: 'Other Towers');
    creator = await api.createMember(
        name: 'Vcreator ${s.letters}', email: 'bug104.creator.${s.digits}@example.com', apartment: 'Other Towers');
    postText = 'Morning walk notes from ${owner.name}';
    await api.createPost(owner, postText);
    groupTitle = 'Hidden ${s.letters}';
    groupId = await api.createGroup(creator, groupTitle, description: 'Members only see who lets them.');
    await api.joinGroup(owner, groupId);
  });

  final privateTitle = find.text('This profile is private');

  /// Home → Members → search the owner → their profile.
  Future<void> openOwnerFromMembers(WidgetTester tester) async {
    final members = find.byType(MembersScreen);
    if (members.evaluate().isEmpty) {
      await tapOn(tester, find.descendant(of: find.byType(HomeFeedScreen), matching: find.text('Members')).first,
          settle: const Duration(milliseconds: 800));
      await pumpUntil(tester, members, reason: 'Home → Members opens the members list');
      await typeInto(tester, find.descendant(of: members, matching: find.byType(TextField)), owner.name);
    }
    final row = find.descendant(of: members, matching: find.widgetWithText(ListTile, owner.name));
    await pumpUntil(tester, row, reason: 'the owner is listed while their profile is visible');
    await tapOn(tester, row, settle: const Duration(milliseconds: 800));
    await pumpUntil(tester, find.byType(UserProfileScreen));
  }

  /// Waits for the open profile to settle on either the private state or the owner's name.
  Future<bool> profileShowsPrivate(WidgetTester tester) async {
    final profile = find.byType(UserProfileScreen);
    final name = find.descendant(of: profile, matching: find.text(owner.name));
    final private = find.descendant(of: profile, matching: privateTitle);
    await pumpUntilTrue(tester, () => name.evaluate().isNotEmpty || private.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 15), reason: 'the profile loads');
    return private.evaluate().isNotEmpty;
  }

  testWidgets('"Only me" makes the profile and its View More private, and each open refetches', (tester) async {
    await api.setVisibility(owner, 'all');
    await launchApp(tester);
    await loginWithEmail(tester, viewer.email, viewer.password);

    await openOwnerFromMembers(tester);
    expect(await profileShowsPrivate(tester), isFalse, reason: 'visible to everyone at first');
    expect(find.text(postText), findsWidgets, reason: 'their posts show on the profile');
    expect(find.text('View More'), findsOneWidget);
    await screenshot(tester, 'bug104_profile_visible');

    // The owner hides the profile while the viewer is looking at it.
    await api.setVisibility(owner, 'only_me');
    await tapOn(tester, find.text('View More'), settle: const Duration(milliseconds: 800));
    final posts = find.byType(UserPostsScreen);
    await pumpUntil(tester, find.descendant(of: posts, matching: privateTitle),
        timeout: const Duration(seconds: 10), reason: 'View More says the profile is private, at once');
    expect(find.descendant(of: posts, matching: find.text(postText)), findsNothing);
    expect(find.descendant(of: posts, matching: find.text('Retry')), findsNothing, reason: 'no Retry for a setting');
    expect(find.descendant(of: posts, matching: find.byIcon(Icons.chevron_left)), findsNothing,
        reason: 'no second back button under the app bar\'s');
    expect(find.descendant(of: posts, matching: find.byType(BackButton)), findsOneWidget);
    await screenshot(tester, 'bug104_view_more_private');

    await goBack(tester); // to the profile (still the copy loaded before)
    await pumpUntilGone(tester, posts);
    await goBack(tester); // to Members
    await pumpUntilGone(tester, find.byType(UserProfileScreen));

    // Opened again: refetched, so it's private now, with no restart.
    await openOwnerFromMembers(tester);
    expect(await profileShowsPrivate(tester), isTrue, reason: '"Only me" → private on the next open');
    expect(find.text(postText), findsNothing);
    expect(find.text('Retry'), findsNothing);
    await screenshot(tester, 'bug104_profile_private_only_me');
    await goBack(tester);
    await pumpUntilGone(tester, find.byType(UserProfileScreen));

    // Apartment rule: the viewer lives in another apartment of the same area.
    await api.setVisibility(owner, 'apartment');
    await openOwnerFromMembers(tester);
    expect(await profileShowsPrivate(tester), isTrue, reason: '"My apartment" leaves out another apartment');
    await goBack(tester);
    await pumpUntilGone(tester, find.byType(UserProfileScreen));

    // Area rule: same area → visible again, again without a restart.
    await api.setVisibility(owner, 'area');
    await openOwnerFromMembers(tester);
    expect(await profileShowsPrivate(tester), isFalse, reason: '"My area" includes the viewer\'s area');
    expect(find.text('View More'), findsOneWidget);
    await tapOn(tester, find.text('View More'), settle: const Duration(milliseconds: 800));
    await pumpUntil(tester, find.descendant(of: posts, matching: find.text(postText)),
        reason: 'View More lists the posts again');
    await screenshot(tester, 'bug104_area_visible_posts');
  });

  testWidgets('the group Members sheet leaves out a private member and says how many', (tester) async {
    await api.setVisibility(owner, 'only_me');
    final asViewer = await api.send('GET', '/groups/$groupId/members', token: viewer.token);
    expect((asViewer.data as Map)['meta'], {'hiddenCount': 1}, reason: 'the API counts the hidden member');

    await launchApp(tester);
    await loginWithEmail(tester, viewer.email, viewer.password);
    await openGroupFromGroupsTab(tester, groupTitle);

    await tapOn(tester, find.descendant(of: find.byType(GroupProfileScreen), matching: find.text('2 Members')),
        settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, inSheet(find.textContaining('Members (')), reason: 'the Members sheet loads');
    expect(inSheet(find.text('Members (2)')), findsOneWidget, reason: 'the count stays honest');
    expect(inSheet(find.text(creator.name)), findsOneWidget);
    expect(inSheet(find.text(owner.name)), findsNothing, reason: 'the private member is left out');
    final line = inSheet(find.text('1 member has a private profile'));
    expect(line, findsOneWidget);
    expect(find.descendant(of: find.ancestor(of: line, matching: find.byType(Row)).first,
        matching: find.byIcon(Icons.lock_outline_rounded)), findsOneWidget);
    await screenshot(tester, 'bug104_group_members_hidden');
    await dismissSheet(tester);
  });

  testWidgets('the group creator still sees every member', (tester) async {
    await api.setVisibility(owner, 'only_me');
    await launchApp(tester);
    await loginWithEmail(tester, creator.email, creator.password);
    await openGroupFromGroupsTab(tester, groupTitle);

    await tapOn(tester, find.descendant(of: find.byType(GroupProfileScreen), matching: find.text('2 Members')),
        settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, inSheet(find.textContaining('Members (')), reason: 'the Members sheet loads');
    expect(inSheet(find.text('Members (2)')), findsOneWidget);
    expect(inSheet(find.text(creator.name)), findsOneWidget);
    expect(inSheet(find.text(owner.name)), findsOneWidget, reason: 'admins see private members too');
    expect(inSheet(find.textContaining('private profile')), findsNothing);
    await screenshot(tester, 'bug104_group_members_creator');
    await dismissSheet(tester);
  });
}
