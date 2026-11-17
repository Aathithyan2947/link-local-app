// UI batch 1 on the device: BUG-075 (Terms links on sign-up), BUG-076 (upload page text),
// BUG-078 (filled bottom-bar icons), BUG-079 (All Members page) and BUG-082 (Group Members
// page), through the real app against the test backend.
//
// Run: see integration_test/support/harness.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/router/app_router.dart';
import 'package:link_local/core/widgets/terms_notice.dart';
import 'package:link_local/features/address/presentation/address_capture_screen.dart';
import 'package:link_local/features/address/presentation/address_verify_screen.dart';
import 'package:link_local/features/auth/presentation/otp_screen.dart';
import 'package:link_local/features/auth/presentation/register_screen.dart';
import 'package:link_local/features/discovery/presentation/group_members_screen.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/discovery/presentation/user_profile_screen.dart';
import 'package:link_local/features/home/presentation/home_shell.dart';
import 'package:link_local/features/members/presentation/members_screen.dart';
import 'package:link_local/features/messages/presentation/chat_screen.dart';

import 'support/harness.dart';

void main() {
  initIntegrationTest();
  final api = TestApi();

  late SeededUser creator; // runs the group
  late SeededUser neighbour; // a member
  late SeededUser viewer; // a member, the one who signs in
  late String stamp;
  late String groupTitle;

  setUpAll(() async {
    final s = uniqueStamp();
    stamp = s.letters;
    creator = await api.createMember(name: 'Bcreator $stamp', email: 'b1.creator.${s.digits}@example.com');
    neighbour = await api.createMember(name: 'Bneighbour $stamp', email: 'b1.neighbour.${s.digits}@example.com');
    viewer = await api.createMember(name: 'Bviewer $stamp', email: 'b1.viewer.${s.digits}@example.com');
    groupTitle = 'Batch $stamp';
    final groupId = await api.createGroup(creator, groupTitle, description: 'Batch one on the device.');
    for (final u in [neighbour, viewer]) {
      await api.joinGroup(u, groupId);
    }
  });

  testWidgets('075 + 076: Terms links on email sign-up and the sign-up code screen; upload page text', (tester) async {
    await launchApp(tester);
    await tapOn(tester, find.text('Sign Up'), settle: const Duration(milliseconds: 800));
    await pumpUntil(tester, find.byType(RegisterScreen), reason: 'Sign Up opens the register screen');

    // Mobile tab: no notice here (the code screen shows it).
    expect(find.byType(TermsNotice), findsNothing);
    await tapOn(tester, find.text('Email'));
    await pumpUntil(tester, find.byType(TermsNotice), reason: 'the email form shows the Terms notice');
    await scrollIntoView(tester, find.byType(TermsNotice));
    await screenshot(tester, 'b1_075_email_signup_terms');

    await tester.tapOnText(find.textRange.ofSubstring('Terms of Service'));
    await pumpUntil(tester, find.byType(LegalPage), reason: 'Terms of Service opens its page');
    expect(find.widgetWithText(AppBar, 'Terms of Service'), findsOneWidget);
    await screenshot(tester, 'b1_075_terms_page');
    await goBack(tester);
    await pumpUntilGone(tester, find.byType(LegalPage), reason: 'back returns to sign-up');

    // Mobile sign-up → the code screen shows the notice under Continue.
    await tapOn(tester, find.text('Mobile no.'));
    await typeInto(tester, pillField('Enter your Full Name'), 'Bsignup $stamp');
    await typeInto(tester, pillField('Enter your 10-digit Mobile No.'), uniqueMobile());
    await tapOn(tester, find.widgetWithText(ElevatedButton, 'Send OTP'), settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, find.byType(OtpScreen), reason: 'Send OTP opens the code screen');
    expect(find.byType(TermsNotice), findsOneWidget);
    await screenshot(tester, 'b1_075_otp_terms');

    // Finish signing up (the test backend returns the code, prefilled), then look at the upload
    // page, which sign-up reaches right after the address.
    await tapOn(tester, find.widgetWithText(ElevatedButton, 'Continue'), settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, find.byType(AddressCaptureScreen),
        timeout: const Duration(seconds: 40), reason: 'a new member is asked for their address');
    appContainer(tester).read(routerProvider).go(Routes.verifyAddress);
    await pumpUntil(tester, find.byType(AddressVerifyScreen), reason: 'the upload page opens');
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.widgetWithText(ElevatedButton, 'Submit now'), findsOneWidget);
    await screenshot(tester, 'b1_076_upload_page_top');
    await scrollIntoView(tester, find.widgetWithText(ElevatedButton, 'Submit now'));
    await screenshot(tester, 'b1_076_upload_page_bottom');
  });

  testWidgets('078 + 079 + 082: bottom bar, All Members page, Group Members page', (tester) async {
    await launchApp(tester);
    await loginWithEmail(tester, viewer.email, viewer.password);

    // 078: one filled glyph per tab, whichever is active.
    final bar = find.byType(HomeShell);
    for (final icon in [Icons.home_rounded, Icons.pending, Icons.storefront_rounded, Icons.supervised_user_circle]) {
      expect(find.descendant(of: bar, matching: find.byIcon(icon)), findsOneWidget, reason: '$icon in the bar');
    }
    await screenshot(tester, 'b1_078_home_bottom_bar');

    // 079: Home's Members tile → All members nearby.
    await tapOn(tester, find.text('Members').first, settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, find.byType(MembersScreen), reason: 'the Members tile opens the list');
    await pumpUntil(tester, find.textContaining('Members in', findRichText: true), reason: 'the list loads');
    expect(find.text('All members nearby'), findsOneWidget);
    await typeInto(tester, find.descendant(of: find.byType(MembersScreen), matching: find.byType(TextField)), stamp);
    await pumpUntil(tester, find.text(creator.name), reason: 'search finds the seeded members');
    expect(find.text(neighbour.name), findsOneWidget);
    expect(find.textContaining('Welcome'), findsWidgets, reason: 'members who just joined are welcomed');
    await screenshot(tester, 'b1_079_all_members');
    await tapOn(tester, find.textContaining('Members in', findRichText: true), settle: const Duration(milliseconds: 700));
    await pumpUntil(tester, find.text('My Society'), reason: 'the dropdown lists the scopes');
    await screenshot(tester, 'b1_079_scope_sheet');
    await tapOn(tester, find.text('City').last, settle: const Duration(milliseconds: 900));
    await goBack(tester);
    await pumpUntilGone(tester, find.byType(MembersScreen), reason: 'back returns Home');

    // 082: the group's Members opens the Group Members page.
    await openGroupFromGroupsTab(tester, groupTitle);
    await tapOn(
      tester,
      find.descendant(of: find.byType(GroupProfileScreen), matching: find.text('3 Members')),
      settle: const Duration(milliseconds: 900),
    );
    await pumpUntil(tester, find.byType(GroupMembersScreen), reason: 'Members opens the page');
    await pumpUntil(tester, find.text('Total Members 3'), reason: 'the page loads');
    expect(find.text('Admin (1)'), findsOneWidget);
    expect(find.text('Members (2)'), findsOneWidget);
    final mine = find.byKey(ValueKey('group-member-${viewer.userId}'));
    expect(find.descendant(of: mine, matching: find.text('You')), findsOneWidget);
    expect(find.textContaining('Joined '), findsNWidgets(3));
    await screenshot(tester, 'b1_082_group_members');

    await tapOn(tester, find.byTooltip('Message ${neighbour.name}'), settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, find.byType(ChatScreen), reason: 'the chat icon opens the chat');
    await goBack(tester);
    await pumpUntilGone(tester, find.byType(ChatScreen), reason: 'back returns to Group Members');

    await tapOn(tester, find.descendant(of: find.byType(GroupMembersScreen), matching: find.text(neighbour.name)),
        settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, find.byType(UserProfileScreen), reason: 'a name opens their profile');
    await goBack(tester);
    await pumpUntil(tester, find.byType(GroupMembersScreen).hitTestable(), reason: 'back returns to the page');
  });
}
