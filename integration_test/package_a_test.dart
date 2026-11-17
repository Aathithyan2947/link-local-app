// Package A on the device: BUG-108 (Write a Post from the Figma: title, type, notify), BUG-115
// ("Post in" / "Members from": who it's for) and BUG-080 (Create Group from the Figma), through
// the real app against the test backend. Each audience is checked against neighbours who are
// in it and out of it.
//
// Run: see integration_test/support/harness.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/discovery/presentation/create_event_screen.dart';
import 'package:link_local/features/discovery/presentation/create_group_screen.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/feed/presentation/create_post_screen.dart';
import 'package:link_local/features/home/presentation/home_feed_screen.dart';
import 'package:link_local/features/home/presentation/home_shell.dart';

import 'support/harness.dart';

void main() {
  initIntegrationTest();
  final api = TestApi();

  late SeededUser author; // building A on lane A
  late SeededUser laneNeighbour; // building B on lane A
  late SeededUser otherLane; // building C on lane B, same area
  late String stamp;

  /// A verified member in area 1 at [building] on [lane].
  Future<SeededUser> member(String label, String building, String lane) async {
    final s = uniqueStamp();
    final email = 'pa.$label.${s.digits}@example.com';
    final reg = TestApi.ok(
      await api.send('POST', '/auth/register', body: {
        'name': 'Pa $label $stamp',
        'email': email,
        'password': defaultPassword,
        'userType': 'resident',
      }),
      'register $email',
    )['data'] as Map<String, dynamic>;
    final token = reg['accessToken'] as String;
    final userId = (reg['user'] as Map<String, dynamic>)['id'] as int;
    TestApi.ok(
      await api.send('POST', '/addresses', token: token, body: {
        'cityId': 1,
        'areaId': 1,
        'apartment': building,
        'lane1': lane,
        'fullAddress': '1, $building, $lane',
      }),
      'address for $email',
    );
    TestApi.ok(
      await api.send('PATCH', '/admin/members/$userId/status', token: await api.adminToken(), body: {'isVerified': true}),
      'verify $email',
    );
    final profile = TestApi.ok(await api.send('GET', '/profiles/me', token: token), 'profile')['data'];
    return SeededUser(
      userId: userId,
      profileId: profile['id'] as int,
      name: 'Pa $label $stamp',
      email: email,
      password: defaultPassword,
      token: token,
    );
  }

  setUpAll(() async {
    stamp = uniqueStamp().letters;
    author = await member('author', 'Atower $stamp', 'Alane $stamp');
    laneNeighbour = await member('laneneighbour', 'Btower $stamp', 'Alane $stamp');
    otherLane = await member('otherlane', 'Ctower $stamp', 'Blane $stamp');
  });

  Future<List<Map<String, dynamic>>> posts(SeededUser u) async =>
      (TestApi.ok(await api.send('GET', '/posts?pageSize=50', token: u.token), 'posts')['data'] as List)
          .cast<Map<String, dynamic>>();

  Future<void> openCreate(WidgetTester tester, String tile) async {
    await tapOn(tester, find.descendant(of: find.byType(HomeShell), matching: find.byIcon(Icons.add)),
        settle: const Duration(milliseconds: 700));
    await tapOn(tester, find.text(tile), settle: const Duration(milliseconds: 900));
  }

  /// Waits for the picker to show the member's own place names (their profile has loaded).
  Future<void> placesLoaded(WidgetTester tester) => pumpUntilTrue(
        tester,
        () => find.text('Your area').evaluate().isEmpty,
        timeout: const Duration(seconds: 20),
        reason: 'the picker shows the member\'s area by name',
      );

  testWidgets('108 + 115: Write a Post for My Lane reaches the lane, not the next lane', (tester) async {
    await launchApp(tester);
    await loginWithEmail(tester, author.email, author.password);
    await openCreate(tester, 'Create a Post');
    await pumpUntil(tester, find.byType(CreatePostScreen), reason: 'the + menu opens Write a Post');
    await placesLoaded(tester);
    await screenshot(tester, 'pkgA_108_write_post');

    await tapOn(tester, find.byKey(const ValueKey('audience-picker')), settle: const Duration(milliseconds: 700));
    await pumpUntil(tester, find.text('My Lane'), reason: 'the picker lists the audiences');
    expect(find.text('Atower $stamp'), findsOneWidget, reason: 'My Society shows the building by name');
    await screenshot(tester, 'pkgA_115_post_in_sheet');
    await tapOn(tester, find.text('My Lane'), settle: const Duration(milliseconds: 700));
    expect(find.text('Alane $stamp'), findsOneWidget, reason: 'Post in: <lane>');

    final title = 'Lane meeting $stamp';
    await typeInto(tester, find.widgetWithText(TextField, "What's your post about?"), title);
    await tapOn(tester, find.text('General'), settle: const Duration(milliseconds: 600));
    await tapOn(tester, find.text('Query').last, settle: const Duration(milliseconds: 600));
    await typeInto(tester, find.widgetWithText(TextField, 'Write your post....'), 'Sunday 10 am at the gate.');
    await tapOn(tester, find.byType(Switch));
    await screenshot(tester, 'pkgA_108_write_post_filled');
    await tapOn(tester, find.text('Post Discussion'), settle: const Duration(milliseconds: 900));
    await pumpUntilGone(tester, find.byType(CreatePostScreen), timeout: const Duration(seconds: 20),
        reason: 'posting closes Write a Post');

    final mine = (await posts(author)).where((p) => p['title'] == title).toList();
    expect(mine, hasLength(1), reason: 'the post was created with its title');
    expect(mine.single['audience'], 'lane');
    expect(mine.single['postType'], 'query');
    expect(mine.single['notifyReplies'], isFalse);
    expect((await posts(laneNeighbour)).any((p) => p['title'] == title), isTrue,
        reason: 'a neighbour on the same lane sees it');
    expect((await posts(otherLane)).any((p) => p['title'] == title), isFalse,
        reason: 'a neighbour on the next lane does not');

    // Home builds its sections lazily; the discussions sit below the providers.
    await pumpFor(tester, const Duration(seconds: 2));
    await tester.scrollUntilVisible(
      find.text(title),
      400,
      scrollable: find.descendant(of: find.byType(HomeFeedScreen), matching: find.byType(Scrollable)).first,
      maxScrolls: 30,
    );
    await pumpFor(tester, const Duration(milliseconds: 500));
    await screenshot(tester, 'pkgA_108_home_card_with_title');
  });

  testWidgets('080 + 115: Create Group from the Figma, for My Society', (tester) async {
    await launchApp(tester);
    await loginWithEmail(tester, author.email, author.password);
    await openCreate(tester, 'Start a Group');
    await pumpUntil(tester, find.byType(CreateGroupScreen), reason: 'the + menu opens Create Group');
    await placesLoaded(tester);
    await screenshot(tester, 'pkgA_080_create_group');

    await tapOn(tester, find.byKey(const ValueKey('audience-picker')), settle: const Duration(milliseconds: 700));
    await tapOn(tester, find.text('My Society'), settle: const Duration(milliseconds: 700));
    final name = 'Society walkers $stamp';
    await typeInto(tester, find.widgetWithText(TextFormField, 'Group name'), name);
    await tapOn(tester, find.widgetWithText(ElevatedButton, 'Create Group'), settle: const Duration(milliseconds: 900));
    await pumpUntil(tester, find.byType(GroupProfileScreen), timeout: const Duration(seconds: 20),
        reason: 'creating opens the new group');
    await screenshot(tester, 'pkgA_080_group_created');

    Future<List<dynamic>> groups(SeededUser u) async =>
        TestApi.ok(await api.send('GET', '/groups?q=$stamp&pageSize=50', token: u.token), 'groups')['data'] as List;
    final made = (await groups(author)).where((g) => g['title'] == name).toList();
    expect(made, hasLength(1));
    expect(made.single['audience'], 'society');
    expect((await groups(laneNeighbour)).any((g) => g['title'] == name), isFalse,
        reason: 'another building on the same lane does not see a My Society group');
  });

  testWidgets('115: Host an Event has the same "Post in" picker', (tester) async {
    await launchApp(tester);
    await loginWithEmail(tester, author.email, author.password);
    await openCreate(tester, 'Host an Event');
    await pumpUntil(tester, find.byType(CreateEventScreen), reason: 'the + menu opens Host an Event');
    await placesLoaded(tester);
    expect(find.byKey(const ValueKey('audience-picker')), findsOneWidget);
    await screenshot(tester, 'pkgA_115_host_event');
    await goBack(tester);
  });
}
