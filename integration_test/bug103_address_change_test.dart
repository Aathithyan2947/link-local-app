// BUG-103: a verified member changes their own registered address (My Profile → pencil by the
// address → Change address → Confirm). The app re-reads the signed-in user (no longer
// verified), opens the address-proof upload screen (back is allowed), the Home "Upload your
// address proof" reminder shows again even if it was dismissed for the old address, and gated
// actions show the "Address proof mandatory" popup until a new proof is uploaded, all without
// restarting the app.
//
// Uploading a proof can't be exercised here: the test backend's file storage is a dummy, so
// uploads fail by design. The tests stop at the popup and the upload screen it opens.
//
// Run: see integration_test/support/harness.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/address/presentation/address_capture_screen.dart';
import 'package:link_local/features/address/presentation/address_proof_gate.dart';
import 'package:link_local/features/address/presentation/address_proof_screen.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/feed/presentation/create_post_screen.dart';
import 'package:link_local/features/feed/presentation/widgets/discussion_card.dart';
import 'package:link_local/features/home/presentation/home_feed_screen.dart';
import 'package:link_local/features/home/presentation/home_shell.dart';
import 'package:link_local/features/home/presentation/tabs/profile_tab.dart';

import 'support/harness.dart';

const _oldApartment = 'Other Towers';
const _oldAddress = '$_oldApartment, Kasarvadavali, Thane';
const _newBuilding = 'Lotus Heights';

void main() {
  initIntegrationTest();
  final api = TestApi();

  late SeededUser host; // runs the groups the member uses
  late String memberGroup;
  late String otherGroup;
  late String groupPostText;
  late int memberGroupId;
  late int otherGroupId;

  setUpAll(() async {
    final s = uniqueStamp();
    host = await api.createMember(name: 'Ahost ${s.letters}', email: 'bug103.host.${s.digits}@example.com');
    memberGroup = 'Neighbours ${s.letters}';
    otherGroup = 'Gardeners ${s.letters}';
    memberGroupId = await api.createGroup(host, memberGroup, description: 'Lane updates.');
    otherGroupId = await api.createGroup(host, otherGroup, description: 'Weekend planting.');
    groupPostText = 'Water cut tomorrow on ${s.letters} lane';
    TestApi.ok(
        await api.send('POST', '/groups/$memberGroupId/posts', token: host.token, body: {'textContent': groupPostText}),
        'group post');
  });

  /// A resident verified by an admin at Other Towers, Kasarvadavali.
  Future<SeededUser> verifiedMember(String tag) {
    final s = uniqueStamp();
    return api.createMember(
        name: 'Amover ${s.letters}', email: 'bug103.$tag.${s.digits}@example.com', apartment: _oldApartment);
  }

  final reminder = find.text('Upload your address proof');
  Finder homeReminder() => find.descendant(of: find.byType(HomeFeedScreen), matching: reminder);
  final popupTitle = find.text('Address proof mandatory');

  /// The popup for [action], then "Not now". Nothing behind it opens.
  Future<void> expectProofPopup(WidgetTester tester, String action, {String? shot}) async {
    await pumpUntil(tester, popupTitle, timeout: const Duration(seconds: 15),
        reason: 'the "Address proof mandatory" popup for "$action"');
    expect(find.byType(AddressProofRequiredDialog), findsOneWidget);
    expect(find.text('Upload your address proof to $action.'), findsOneWidget);
    if (shot != null) await screenshot(tester, shot);
    await tapOn(tester, find.text('Not now'), settle: const Duration(milliseconds: 600));
    await pumpUntilGone(tester, popupTitle);
  }

  /// Home → profile icon → My Profile (the member's own profile page).
  Future<void> openMyProfile(WidgetTester tester) async {
    final profileIcon = find.descendant(of: find.byType(HomeFeedScreen), matching: find.byIcon(Icons.person));
    await pumpUntil(tester, profileIcon, reason: 'Home has loaded its header');
    await tapOn(tester, profileIcon, settle: const Duration(milliseconds: 800));
    await pumpUntil(tester, find.byType(ProfileTab));
    final myProfile = find.text('My Profile');
    final page = find.byType(ServiceProviderDetailScreen);
    // The item needs the profile id, loaded with the tab; tap again if the first tap was early.
    for (var i = 0; i < 5 && page.evaluate().isEmpty; i++) {
      await tapOn(tester, myProfile, settle: const Duration(milliseconds: 1200));
    }
    await pumpUntil(tester, page, reason: 'My Profile opens');
  }

  /// My Profile → pencil next to the address → fill the new address → Confirm.
  Future<void> changeAddressInApp(WidgetTester tester) async {
    await openMyProfile(tester);
    final address = find.text(_oldAddress);
    await pumpUntil(tester, address, reason: 'My Profile shows the registered address');
    final pencil = find.descendant(
        of: find.ancestor(of: address, matching: find.byType(Row)).first, matching: find.byIcon(Icons.edit_outlined));
    expect(pencil, findsOneWidget, reason: 'a pencil next to the address');
    await tapOn(tester, pencil, settle: const Duration(milliseconds: 900));

    await pumpUntil(tester, find.byType(AddressCaptureScreen));
    expect(find.text('Change address'), findsOneWidget, reason: 'the edit-mode app bar');
    await pumpUntil(tester, pillField('Search in Mumbai'), reason: 'it starts on the member\'s city');
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tapOn(tester, find.widgetWithText(ElevatedButton, 'Next'), settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, find.text('Confirm your Address'), reason: 'the confirm sheet opens');

    await typeInto(tester, pillField('Flat No. / Wing / House / Plot'), 'B-204');
    await typeInto(tester, pillField('Building / Apartment name'), _newBuilding);
    await typeInto(tester, pillField('Area'), 'Kasarvadavali');
    await typeInto(tester, pillField('Pincode'), '400615');
    await screenshot(tester, 'bug103_confirm_new_address');
    await tapOn(tester, find.widgetWithText(ElevatedButton, 'Confirm'), settle: const Duration(milliseconds: 600));
    await pumpUntil(tester, find.byType(AddressProofScreen), reason: 'saving goes straight to proof upload');
  }

  Future<void> backToHome(WidgetTester tester) async {
    for (var i = 0; i < 4 && find.byType(HomeFeedScreen).hitTestable().evaluate().isEmpty; i++) {
      await goBack(tester);
    }
    await pumpUntil(tester, find.byType(HomeFeedScreen).hitTestable(), reason: 'back on Home');
  }

  testWidgets(
      'a changed address unverifies the member, opens proof upload (back allowed) and brings the reminder back',
      (tester) async {
    final member = await verifiedMember('flow');
    final oldAddressId = (await api.myAddress(member.token))!['id'] as int;
    await launchApp(tester);
    await loginWithEmail(tester, member.email, member.password);
    final auth = appContainer(tester);
    expect(auth.read(authControllerProvider).user?.isVerified, isTrue, reason: 'verified before the move');

    // Verified by the admin with no proof document on file: no reminder, like the action gate.
    // (Dismissing it per address is covered by test/address_change_proof_test.dart.)
    await pumpUntil(tester, find.byType(HomeFeedScreen).hitTestable(), reason: 'Home has loaded');
    await pumpFor(tester, const Duration(seconds: 3));
    expect(homeReminder(), findsNothing, reason: 'a verified member is not asked for a proof');

    // Verified: creating a post opens the editor, no popup.
    final fab = find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.add && w.size == 30);
    await tapOn(tester, fab, settle: const Duration(milliseconds: 700));
    await tapOn(tester, find.text('Create a Post'), settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, find.byType(CreatePostScreen), reason: 'a verified member may post');
    expect(popupTitle, findsNothing);
    await goBack(tester);
    await pumpUntilGone(tester, find.byType(CreatePostScreen));

    await changeAddressInApp(tester);

    // The upload screen for the new address, with a way back.
    final proof = find.byType(AddressProofScreen);
    expect(find.descendant(of: proof, matching: find.text('Address Proof')), findsOneWidget);
    await pumpUntil(tester, find.descendant(of: proof, matching: find.textContaining(_newBuilding)),
        reason: 'the proof screen shows the new address');
    expect(find.descendant(of: proof, matching: find.text('Not uploaded')), findsOneWidget);
    expect(find.descendant(of: proof, matching: find.widgetWithText(ElevatedButton, 'Submit proof')), findsOneWidget);
    expect(find.descendant(of: proof, matching: find.byType(BackButton)), findsOneWidget, reason: 'back is allowed');
    expect(find.byType(AddressCaptureScreen), findsNothing, reason: 'the address form was replaced');
    await screenshot(tester, 'bug103_proof_screen_after_change');

    // The app re-read the user: no longer verified, without a restart.
    await pumpUntilTrue(tester, () => auth.read(authControllerProvider).user?.isVerified == false,
        timeout: const Duration(seconds: 15), reason: 'the signed-in user is refreshed as unverified');
    final me = await api.me(member.token);
    expect(me['isVerified'], isFalse, reason: 'the server unverified the member with the move');
    final newAddress = (await api.myAddress(member.token))!;
    expect(newAddress['id'], isNot(oldAddressId));
    expect(newAddress['apartment'], _newBuilding);

    // Back from the upload screen lands on My Profile, showing the new address.
    await goBack(tester);
    await pumpUntilGone(tester, proof);
    await pumpUntil(tester, find.byType(ServiceProviderDetailScreen).hitTestable());
    await pumpUntil(tester, find.textContaining(_newBuilding), reason: 'My Profile refetched the new address');
    expect(find.text(_oldAddress), findsNothing);

    // Home: the reminder now shows, for the new address.
    await backToHome(tester);
    await pumpUntil(tester, homeReminder(), reason: 'the reminder shows again for the new address');
    await screenshot(tester, 'bug103_home_reminder_back');

    // A gated action now asks for the proof first.
    await tapOn(tester, fab, settle: const Duration(milliseconds: 700));
    await tapOn(tester, find.text('Create a Post'), settle: const Duration(milliseconds: 600));
    await expectProofPopup(tester, 'create a post', shot: 'bug103_popup_create_post');
    expect(find.byType(CreatePostScreen), findsNothing, reason: 'the editor does not open');
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('after the change, joining, posting, liking and commenting all ask for the new proof',
      (tester) async {
    final member = await verifiedMember('gates');
    await api.joinGroup(member, memberGroupId); // joined while still verified
    await launchApp(tester);
    await loginWithEmail(tester, member.email, member.password);
    final auth = appContainer(tester);

    await changeAddressInApp(tester);
    await pumpUntilTrue(tester, () => auth.read(authControllerProvider).user?.isVerified == false,
        timeout: const Duration(seconds: 15), reason: 'the signed-in user is refreshed as unverified');
    await backToHome(tester);

    // In a group they're in: Post, like and comment.
    await openGroupFromGroupsTab(tester, memberGroup);
    final page = find.byType(GroupProfileScreen);
    await tapOn(tester, find.descendant(of: page, matching: find.widgetWithText(TextButton, 'Post')));
    await expectProofPopup(tester, 'post in a group', shot: 'bug103_popup_group_post');

    final card = find.widgetWithText(DiscussionCard, groupPostText);
    await pumpUntil(tester, card, reason: 'the group\'s discussion is listed');
    await tapOn(tester, find.descendant(of: card, matching: find.byIcon(Icons.favorite_border)));
    await expectProofPopup(tester, 'like a post');
    expect(find.descendant(of: card, matching: find.byIcon(Icons.favorite)), findsNothing, reason: 'not liked');

    await tapOn(tester, find.descendant(of: card, matching: find.byIcon(Icons.mode_comment_outlined)),
        settle: const Duration(milliseconds: 900));
    final composer = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Add a comment…');
    await pumpUntil(tester, composer, reason: 'the comments sheet opens');
    await tester.tap(composer);
    await expectProofPopup(tester, 'comment on a post', shot: 'bug103_popup_comment');
    await dismissSheet(tester);
    await goBack(tester); // the group page
    await pumpUntilGone(tester, page);

    // A group they aren't in: Join, and the popup's button opens the upload screen.
    await openGroupFromGroupsTab(tester, otherGroup);
    await tapOn(tester, find.widgetWithText(ElevatedButton, 'Join Group'));
    await pumpUntil(tester, popupTitle, reason: 'Join asks for the proof');
    expect(find.text('Upload your address proof to join a group.'), findsOneWidget);
    await screenshot(tester, 'bug103_popup_join_group');
    await tapOn(tester, find.widgetWithText(ElevatedButton, 'Upload address proof'),
        settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, find.byType(AddressProofScreen), reason: '"Upload address proof" opens the upload screen');
    await pumpUntil(tester, find.textContaining(_newBuilding), reason: 'for the new address');
    final members = TestApi.ok(
        await api.send('GET', '/groups/$otherGroupId/members', token: host.token), 'members of $otherGroup');
    expect([for (final m in members['data'] as List) (m as Map)['userId']], isNot(contains(member.userId)),
        reason: 'nothing was joined');
  });
}
