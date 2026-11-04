// Item 3: in a group's Members sheet, each name (with a chevron) opens that member's profile
// over the sheet: a resident → their public profile (UserProfileScreen), a service provider →
// their provider page as visitors see it (ServiceProviderDetailScreen), and the viewer's own row
// → their own profile page in owner view (ServiceProviderDetailScreen, as My Profile opens it).
// Back returns to the still-open sheet each time. The members API sends profileId and
// isServiceProvider for this.
//
// Run: see integration_test/support/harness.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/discovery/presentation/user_profile_screen.dart';

import 'support/harness.dart';

void main() {
  initIntegrationTest();
  final api = TestApi();

  late SeededUser creator; // a resident who runs the group
  late SeededUser neighbour; // a resident member
  late SeededUser baker; // a service provider member (Home baker)
  late SeededUser viewer; // a resident member, the one who signs in
  late String groupTitle;
  late int groupId;

  setUpAll(() async {
    final s = uniqueStamp();
    creator = await api.createMember(name: 'Lcreator ${s.letters}', email: 'item3.creator.${s.digits}@example.com');
    neighbour = await api.createMember(
      name: 'Lneighbour ${s.letters}',
      email: 'item3.neighbour.${s.digits}@example.com',
    );
    baker = await api.createMember(name: 'Lbaker ${s.letters}', email: 'item3.baker.${s.digits}@example.com');
    // A Home baker (service type 1) who finished onboarding: "Shop name" (field 17) is required.
    TestApi.ok(
      await api.send('PATCH', '/profiles/me/user-type', token: baker.token, body: {'userType': 'service_provider'}),
      'make ${baker.email} a provider',
    );
    TestApi.ok(
      await api.send(
        'POST',
        '/profiles/me/service-types',
        token: baker.token,
        body: {
          'subcategoryIds': [1],
        },
      ),
      'Home baker service',
    );
    TestApi.ok(
      await api.send(
        'PUT',
        '/profiles/me/custom-fields',
        token: baker.token,
        body: {
          'values': [
            {'fieldId': 17, 'value': 'Lbakes ${s.letters}'},
            {'fieldId': 18, 'value': 'No'},
          ],
        },
      ),
      'baker questions',
    );
    TestApi.ok(await api.send('POST', '/profiles/me/onboarding-complete', token: baker.token), 'baker onboarding');
    viewer = await api.createMember(name: 'Lviewer ${s.letters}', email: 'item3.viewer.${s.digits}@example.com');
    groupTitle = 'Linked ${s.letters}';
    groupId = await api.createGroup(creator, groupTitle, description: 'Who is who on the lane.');
    for (final u in [neighbour, baker, viewer]) {
      await api.joinGroup(u, groupId);
    }
  });

  Finder memberRow(String name) => inSheet(find.widgetWithText(ListTile, name));

  Future<void> openMembersSheet(WidgetTester tester) async {
    await tapOn(
      tester,
      find.descendant(of: find.byType(GroupProfileScreen), matching: find.text('4 Members')),
      settle: const Duration(milliseconds: 900),
    );
    await pumpUntil(tester, inSheet(find.text('Members (4)')), reason: 'the Members sheet loads');
  }

  /// Taps [name]'s row and waits for [page] to be the screen on top.
  Future<void> openRow(WidgetTester tester, String name, Finder page) async {
    await tapOn(tester, memberRow(name), settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, page.hitTestable(), reason: 'tapping $name opens their profile');
  }

  /// Back from the profile [page]: it closes and the Members sheet is there again, as it was.
  Future<void> backToSheet(WidgetTester tester, Finder page) async {
    await goBack(tester);
    await pumpUntilGone(tester, page, reason: 'back closes the profile');
    await pumpUntil(tester, inSheet(find.text('Members (4)')), reason: 'back returns to the Members sheet');
    for (final u in [creator, neighbour, baker, viewer]) {
      expect(memberRow(u.name), findsOneWidget, reason: '${u.name} is still listed');
    }
    expect(find.byType(GroupProfileScreen), findsOneWidget, reason: 'the group page is still under the sheet');
  }

  testWidgets(
    'each Members row opens that member\'s profile (resident, provider, your own in owner view); back returns '
    'to the sheet',
    (tester) async {
      // What the sheet is built from: who each member is and which page their row opens.
      final listed = TestApi.ok(await api.send('GET', '/groups/$groupId/members', token: viewer.token), 'members');
      final byUser = <dynamic, Map>{for (final m in listed['data'] as List) (m as Map)['userId']: m};
      expect(byUser.keys.toSet(), {creator.userId, neighbour.userId, baker.userId, viewer.userId});
      for (final u in [creator, neighbour, baker, viewer]) {
        expect(byUser[u.userId]!['profileId'], u.profileId, reason: 'the API sends ${u.name}\'s profileId');
        expect(byUser[u.userId]!['isServiceProvider'], u == baker, reason: 'isServiceProvider for ${u.name}');
      }

      await launchApp(tester);
      await loginWithEmail(tester, viewer.email, viewer.password);
      await openGroupFromGroupsTab(tester, groupTitle);
      await openMembersSheet(tester);

      // Every row, the viewer's own included, carries a chevron.
      for (final u in [creator, neighbour, baker, viewer]) {
        final row = memberRow(u.name);
        expect(row, findsOneWidget, reason: '${u.name} is listed');
        expect(
          find.descendant(of: row, matching: find.byIcon(Icons.chevron_right_rounded)),
          findsOneWidget,
          reason: '${u.name}\'s row shows a chevron',
        );
      }
      expect(find.descendant(of: memberRow(creator.name), matching: find.text('Group creator')), findsOneWidget);
      await screenshot(tester, 'item3_members_sheet');

      // A resident → their public profile.
      final userPage = find.byType(UserProfileScreen);
      await openRow(tester, neighbour.name, userPage);
      expect(tester.widget<UserProfileScreen>(userPage).id, neighbour.profileId, reason: 'the neighbour\'s profile');
      await pumpUntil(
        tester,
        find.descendant(of: userPage, matching: find.text(neighbour.name)),
        reason: 'the neighbour\'s profile loads',
      );
      expect(find.descendant(of: userPage, matching: find.text('This profile is private')), findsNothing);
      expect(find.byType(ServiceProviderDetailScreen), findsNothing, reason: 'a resident opens the member page');
      expect(bottomSheet, findsNothing, reason: 'the profile covers the sheet');
      await screenshot(tester, 'item3_resident_profile');
      await backToSheet(tester, userPage);

      // The group creator is a resident too.
      await openRow(tester, creator.name, userPage);
      expect(tester.widget<UserProfileScreen>(userPage).id, creator.profileId);
      await pumpUntil(
        tester,
        find.descendant(of: userPage, matching: find.text(creator.name)),
        reason: 'the creator\'s profile loads',
      );
      await backToSheet(tester, userPage);

      // A service provider → their provider page, as a visitor sees it.
      final providerPage = find.byType(ServiceProviderDetailScreen);
      await openRow(tester, baker.name, providerPage);
      expect(
        tester.widget<ServiceProviderDetailScreen>(providerPage).id,
        baker.profileId,
        reason: 'the baker\'s provider page',
      );
      await pumpUntil(
        tester,
        find.descendant(of: providerPage, matching: find.text('Contact here:')),
        reason: 'the provider page loads in visitor view (contact row)',
      );
      expect(find.descendant(of: providerPage, matching: find.text(baker.name)), findsOneWidget);
      expect(
        find.descendant(of: providerPage, matching: find.text('Contact info:')),
        findsNothing,
        reason: 'not the owner\'s contact editor',
      );
      expect(userPage, findsNothing, reason: 'a provider opens the provider page, not the member page');
      await screenshot(tester, 'item3_provider_page');
      await backToSheet(tester, providerPage);

      // Your own row → your own profile page in owner view, as My Profile opens it.
      await openRow(tester, viewer.name, providerPage);
      expect(
        tester.widget<ServiceProviderDetailScreen>(providerPage).id,
        viewer.profileId,
        reason: 'the viewer\'s own profile',
      );
      await pumpUntil(
        tester,
        find.descendant(of: providerPage, matching: find.text('Contact info:')),
        reason: 'the own profile loads in owner view (contact editor)',
      );
      expect(find.descendant(of: providerPage, matching: find.text(viewer.name)), findsOneWidget);
      expect(
        find.descendant(of: providerPage, matching: find.text('Contact here:')),
        findsNothing,
        reason: 'no Message / Enquire row on your own profile',
      );
      expect(
        find.descendant(of: providerPage, matching: find.byIcon(Icons.camera_alt_rounded)),
        findsOneWidget,
        reason: 'the owner can change their photo',
      );
      expect(userPage, findsNothing);
      await screenshot(tester, 'item3_own_profile');
      await backToSheet(tester, providerPage);

      await dismissSheet(tester);
      expect(find.byType(GroupProfileScreen).hitTestable(), findsOneWidget, reason: 'back on the group page');
    },
  );
}
