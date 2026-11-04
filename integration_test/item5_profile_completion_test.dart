// Item 5: "Complete your profile". The Profile tab shows a completion card between the profile
// card (its Edit button) and the first menu card: "Profile N% complete", a bar, and
// "Next: <the first step left>"; at 100% "Your profile is complete" with no Next. Tapping it
// opens the checklist (GET /profiles/me/completion: 6 steps for a resident, 9 for a provider),
// where each step opens the screen it's filled in on. Closing that screen refreshes both the
// checklist and the card, without a restart. The server works the % out live, so a change
// made elsewhere (an admin verifying the member) shows on the next visit.
//
// Profile photos: uploads go to a dummy Cloudinary on the test backend and the API has no other
// way to set one, so the tests write profiles.photo_url in the local test database
// (link_local_test on localhost:5432, which trusts local connections; never any other). The
// test runs inside the iOS app, which may not start processes, so instead of psql it speaks just
// enough of Postgres' protocol for one statement. The URL points at a tiny server inside the
// test, so the photo really loads (a dead URL would surface as an image error), and every photo
// set here is cleared again at the end.
//
// Run: see integration_test/support/harness.dart.

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/address/presentation/address_proof_screen.dart';
import 'package:link_local/features/business/presentation/add_product_screen.dart';
import 'package:link_local/features/business/presentation/sp_products_screen.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/home/presentation/home_feed_screen.dart';
import 'package:link_local/features/home/presentation/tabs/profile_tab.dart';
import 'package:link_local/features/profile/presentation/profile_completion_screen.dart';
import 'package:link_local/features/profile/presentation/widgets/profile_completion_card.dart';

import 'support/harness.dart';

/// The only database these tests write to directly: the local, seeded test database.
const _testDb = 'link_local_test';

/// Runs one SQL statement on [_testDb] at localhost:5432 and returns its command tag (e.g.
/// "UPDATE 1"). A minimal Postgres client: startup with trust authentication, then one simple
/// query. psql itself can't be started from inside the iOS app.
Future<String> _testDbExec(String sql) async {
  // The Mac's user, who owns the local databases: a simulator app is installed in their home
  // folder (/Users/<name>/Library/Developer/CoreSimulator/...).
  const userOverride = String.fromEnvironment('IT_PG_USER');
  final seen = [Platform.resolvedExecutable, Platform.environment['HOME'] ?? '', Directory.systemTemp.path];
  final user = userOverride.isNotEmpty
      ? userOverride
      : seen.map((p) => RegExp(r'^(?:/private)?/Users/([^/]+)/').firstMatch(p)?.group(1)).nonNulls.firstOrNull;
  if (user == null) throw StateError('no database user in $seen; pass --dart-define=IT_PG_USER=<mac user>');

  // Message types (the first byte of each message).
  final auth = 'R'.codeUnitAt(0), failed = 'E'.codeUnitAt(0), ready = 'Z'.codeUnitAt(0);
  final done = 'C'.codeUnitAt(0), query = 'Q'.codeUnitAt(0), terminate = 'X'.codeUnitAt(0);
  Uint8List int32(int v) => Uint8List(4)..buffer.asByteData().setInt32(0, v);

  final socket = await Socket.connect('localhost', 5432, timeout: const Duration(seconds: 5));
  final incoming = StreamIterator(socket);
  var buf = Uint8List(0);
  // The next message from the server: its type and body.
  Future<(int, Uint8List)> next() async {
    while (true) {
      if (buf.length >= 5) {
        final len = ByteData.sublistView(buf, 1, 5).getInt32(0);
        if (buf.length >= 1 + len) {
          final message = (buf[0], Uint8List.fromList(buf.sublist(5, 1 + len)));
          buf = Uint8List.fromList(buf.sublist(1 + len));
          return message;
        }
      }
      if (!await incoming.moveNext()) throw StateError('$_testDb closed the connection');
      buf = Uint8List.fromList([...buf, ...incoming.current]);
    }
  }

  // An error's message field ("M...").
  String message(Uint8List body) =>
      String.fromCharCodes(body).split('\x00').firstWhere((f) => f.startsWith('M'), orElse: () => 'M?').substring(1);

  try {
    final params = utf8.encode('user\x00$user\x00database\x00$_testDb\x00client_encoding\x00UTF8\x00\x00');
    socket.add([...int32(8 + params.length), ...int32(196608), ...params]); // protocol 3.0
    while (true) {
      final (type, body) = await next();
      if (type == auth && ByteData.sublistView(body).getInt32(0) != 0) {
        throw StateError('$_testDb asked for a password; only trust authentication is supported');
      }
      if (type == failed) throw StateError('connecting to $_testDb: ${message(body)}');
      if (type == ready) break;
    }
    final sqlBytes = utf8.encode('$sql\x00');
    socket.add([query, ...int32(4 + sqlBytes.length), ...sqlBytes]);
    String? tag;
    String? failure;
    while (true) {
      final (type, body) = await next();
      if (type == done) tag = utf8.decode(body.sublist(0, body.length - 1));
      if (type == failed) failure = message(body);
      if (type == ready) break;
    }
    if (failure != null) throw StateError('$sql failed: $failure');
    socket.add([terminate, ...int32(4)]);
    return tag ?? '';
  } finally {
    await incoming.cancel();
    socket.destroy();
  }
}

/// Serves one small PNG on localhost for the seeded profile photos.
class _PhotoServer {
  _PhotoServer._(this._server);
  final HttpServer _server;

  // 1x1 PNG.
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  static Future<_PhotoServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response.headers.contentType = ContentType('image', 'png');
      req.response.add(_png);
      req.response.close();
    });
    return _PhotoServer._(server);
  }

  String urlFor(int profileId) => 'http://localhost:${_server.port}/item5/$profileId.png';

  Future<void> close() => _server.close(force: true);
}

void main() {
  initIntegrationTest();
  final api = TestApi();

  late _PhotoServer photos;
  final withPhoto = <int>[]; // profile ids whose photo_url the tests set

  setUpAll(() async {
    photos = await _PhotoServer.start();
  });

  tearDownAll(() async {
    if (withPhoto.isNotEmpty) {
      await _testDbExec('update profiles set photo_url = null where id in (${withPhoto.join(',')})');
    }
    await photos.close();
  });

  Future<void> givePhoto(SeededUser u) async {
    withPhoto.add(u.profileId);
    final tag = await _testDbExec(
      "update profiles set photo_url = '${photos.urlFor(u.profileId)}' where id = ${u.profileId}",
    );
    expect(tag, 'UPDATE 1', reason: 'the photo of profile ${u.profileId} is set');
  }

  /// A resident in Kasarvadavali with an address and no proof (not admin-verified).
  Future<SeededUser> unverifiedResident(String tag) {
    final s = uniqueStamp();
    return api.createMember(name: 'Pmeter ${s.letters}', email: 'item5.$tag.${s.digits}@example.com', verified: false);
  }

  Future<Map<String, dynamic>> completion(SeededUser u) async =>
      TestApi.ok(await api.send('GET', '/profiles/me/completion', token: u.token), 'completion of ${u.email}')['data']
          as Map<String, dynamic>;

  Future<void> saveAbout(SeededUser u, Map<String, dynamic> body) async =>
      TestApi.ok(await api.send('PUT', '/profiles/me/about', token: u.token, body: body), 'about for ${u.email}');

  // ── The Profile tab and its card ──

  final card = find.byType(ProfileCompletionCard);
  Finder inCard(Finder f) => find.descendant(of: card, matching: f);

  /// Home → profile icon → the Profile tab, its card loaded.
  Future<void> openProfileTab(WidgetTester tester) async {
    final profileIcon = find.descendant(of: find.byType(HomeFeedScreen), matching: find.byIcon(Icons.person));
    await pumpUntil(tester, profileIcon.hitTestable(), reason: 'Home has loaded its header');
    await tapOn(tester, profileIcon, settle: const Duration(milliseconds: 800));
    await pumpUntil(tester, find.byType(ProfileTab).hitTestable(), reason: 'the Profile tab opens');
    await pumpUntil(tester, inCard(find.textContaining('complete')), reason: 'the completion card loads');
  }

  /// Back from the Profile tab to Home: the card's data is dropped with it.
  Future<void> leaveProfileTab(WidgetTester tester) async {
    await goBack(tester);
    await pumpUntilGone(tester, find.byType(ProfileTab), reason: 'back leaves the Profile tab');
    await pumpUntil(tester, find.byType(HomeFeedScreen).hitTestable(), reason: 'back on Home');
  }

  double cardBar(WidgetTester tester) =>
      tester.widget<LinearProgressIndicator>(inCard(find.byType(LinearProgressIndicator))).value!;

  /// The card sits right under the profile card's Edit button and above the first menu card
  /// (the one holding [firstMenuItem]).
  void expectCardBetweenEditAndMenu(WidgetTester tester, String firstMenuItem) {
    final tab = find.byType(ProfileTab);
    final edit = find.descendant(
      of: tab,
      matching: find.ancestor(of: find.text('Edit'), matching: find.byWidgetPredicate((w) => w is OutlinedButton)),
    );
    expect(edit, findsOneWidget, reason: 'the profile card\'s Edit button');
    final menuCard = find.ancestor(
      of: find.descendant(of: tab, matching: find.text(firstMenuItem)),
      matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_PlainSection'),
    );
    expect(menuCard, findsOneWidget, reason: 'the first menu card, with $firstMenuItem');
    final editRect = tester.getRect(edit);
    final cardRect = tester.getRect(card);
    final menuRect = tester.getRect(menuCard);
    expect(cardRect.top, greaterThanOrEqualTo(editRect.bottom), reason: 'the card is below the Edit button');
    expect(cardRect.bottom, lessThanOrEqualTo(menuRect.top), reason: 'the card is above the first menu card');
    expect(menuRect.top - cardRect.bottom, lessThan(1), reason: 'nothing between the card and the menu card');
    expect(cardRect.left, menuRect.left, reason: 'lined up with the menu cards');
    expect(cardRect.width, menuRect.width);
    expect(cardRect.bottom, lessThan(screenSize(tester).height), reason: 'on screen without scrolling');
  }

  // ── The checklist ──

  final checklist = find.byType(ProfileCompletionScreen);
  Finder inChecklist(Finder f) => find.descendant(of: checklist, matching: f);
  final stepCards = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_StepCard');
  Finder stepRow(String title) => find.ancestor(of: inChecklist(find.text(title)), matching: stepCards);

  /// The checklist's list. It builds rows lazily, so a provider's last rows only exist once
  /// scrolled to.
  final checklistList = find.descendant(of: checklist, matching: find.byType(Scrollable));

  Future<void> checklistToTop(WidgetTester tester) async {
    tester.state<ScrollableState>(checklistList.first).position.jumpTo(0);
    await tester.pump();
  }

  /// The step [title] is listed, in its done / to-do state ([hint] when still to do).
  Future<void> expectStep(WidgetTester tester, String title, {required bool done, String? hint}) async {
    final row = stepRow(title);
    await tester.scrollUntilVisible(row, 100, scrollable: checklistList.first);
    expect(row, findsOneWidget, reason: 'the checklist lists "$title"');
    expect(
      find.descendant(of: row, matching: find.text('Done')),
      done ? findsOneWidget : findsNothing,
      reason: '"$title" ${done ? 'is' : 'is not'} done',
    );
    expect(find.descendant(of: row, matching: find.byIcon(Icons.check_circle)), done ? findsOneWidget : findsNothing);
    expect(find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)), done ? findsNothing : findsOneWidget);
    if (hint != null) expect(find.descendant(of: row, matching: find.text(hint)), findsOneWidget);
  }

  /// The checklist's rows, top to bottom, are exactly [titles]: scrolls down through the list,
  /// noting where each row sits in it, then back to the top.
  Future<void> expectStepOrder(WidgetTester tester, List<String> titles) async {
    final position = tester.state<ScrollableState>(checklistList.first).position;
    position.jumpTo(0);
    await tester.pump();
    final at = <String, double>{}; // title → top of its row within the list
    while (true) {
      final built = titles.where((t) => stepRow(t).evaluate().isNotEmpty).toList();
      expect(inChecklist(stepCards), findsNWidgets(built.length), reason: 'no rows other than $titles');
      for (final t in built) {
        expect(stepRow(t), findsOneWidget, reason: '"$t" is listed once');
        at.putIfAbsent(t, () => tester.getTopLeft(stepRow(t)).dy + position.pixels);
      }
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo((position.pixels + 300).clamp(0, position.maxScrollExtent));
      await tester.pump();
    }
    expect(at.keys.toSet(), titles.toSet(), reason: '${titles.length} steps');
    expect(at.keys.toList()..sort((a, b) => at[a]!.compareTo(at[b]!)), titles, reason: 'in checklist order');
    await checklistToTop(tester);
  }

  Future<void> openChecklist(WidgetTester tester) async {
    await tapOn(tester, card, settle: const Duration(milliseconds: 800));
    await pumpUntil(tester, inChecklist(find.textContaining('% complete')), reason: 'the card opens the checklist');
    expect(
      find.descendant(of: checklist, matching: find.text('Complete your profile')),
      findsOneWidget,
      reason: 'the checklist\'s title',
    );
  }

  Future<void> backToChecklist(WidgetTester tester, Finder from) async {
    await goBack(tester);
    await pumpUntilGone(tester, from);
    await pumpUntil(tester, checklist.hitTestable(), reason: 'back on the checklist');
  }

  final aboutSheetTitle = find.text('Edit About');

  /// Taps a step that opens the About editor, checks it opened, and closes it unchanged.
  Future<void> openAndCloseAboutEditor(WidgetTester tester, String step) async {
    await tapOn(tester, stepRow(step), settle: const Duration(milliseconds: 800));
    await pumpUntil(tester, aboutSheetTitle, reason: '"$step" opens the About editor');
    await pumpUntil(tester, inSheet(find.widgetWithText(ElevatedButton, 'Save')), reason: 'the editor loads');
    await tapOn(tester, inSheet(find.byTooltip('Close')), settle: const Duration(milliseconds: 600));
    await pumpUntilGone(tester, aboutSheetTitle, reason: 'Close shuts the unchanged editor');
  }

  /// Taps a step that opens My Profile (owner view of the member's own page), then comes back.
  Future<void> openAndCloseMyProfile(WidgetTester tester, String step, SeededUser u) async {
    final page = find.byType(ServiceProviderDetailScreen);
    await tapOn(tester, stepRow(step), settle: const Duration(milliseconds: 800));
    await pumpUntil(tester, page.hitTestable(), reason: '"$step" opens My Profile');
    expect(tester.widget<ServiceProviderDetailScreen>(page).id, u.profileId, reason: 'the member\'s own profile');
    await pumpUntil(
      tester,
      find.descendant(of: page, matching: find.text('Contact info:')),
      reason: 'My Profile loads in owner view',
    );
    await backToChecklist(tester, page);
  }

  const residentSteps = ['Profile photo', 'Address', 'Address proof', 'About you', 'Education', 'Profession'];

  testWidgets(
    'a partial resident: the card sits under the profile card with the %, a bar and Next; the checklist lists '
    'the six steps and each opens its editor',
    (tester) async {
      final u = await unverifiedResident('partial');
      await givePhoto(u);
      final c = await completion(u);
      expect(c['percent'], 33, reason: 'photo and address of six: 33%');
      expect(
        [for (final i in c['items'] as List) (i as Map)['key']],
        ['photo', 'address', 'addressProof', 'about', 'education', 'profession'],
      );

      await launchApp(tester);
      await loginWithEmail(tester, u.email, u.password);
      await openProfileTab(tester);

      expect(inCard(find.text('Profile 33% complete')), findsOneWidget);
      expect(cardBar(tester), closeTo(0.33, 0.001), reason: 'the bar shows 33%');
      expect(
        inCard(find.text('Next: Upload your address proof')),
        findsOneWidget,
        reason: 'the first step left, in checklist order',
      );
      expect(inCard(find.byIcon(Icons.chevron_right_rounded)), findsOneWidget);
      expect(inCard(find.byIcon(Icons.check_circle)), findsNothing);
      expectCardBetweenEditAndMenu(tester, 'My Profile');
      await screenshot(tester, 'item5_card_partial_resident');

      await openChecklist(tester);
      expect(inChecklist(find.text('33% complete')), findsOneWidget);
      expect(inChecklist(find.text('A complete profile builds trust with neighbours')), findsOneWidget);
      await expectStepOrder(tester, residentSteps);
      await expectStep(tester, 'Profile photo', done: true);
      await expectStep(tester, 'Address', done: true);
      await expectStep(tester, 'Address proof', done: false, hint: 'Upload your address proof');
      await expectStep(tester, 'About you', done: false, hint: 'Tell neighbours about yourself');
      await expectStep(tester, 'Education', done: false, hint: 'Add your education');
      await expectStep(tester, 'Profession', done: false, hint: 'Add your profession');
      for (final providerOnly in ['Services', 'Business details', 'Menu items', 'Charges']) {
        expect(inChecklist(find.text(providerOnly)), findsNothing, reason: 'no "$providerOnly" for a resident');
      }
      await screenshot(tester, 'item5_checklist_partial_resident');

      // Each step opens the screen it's filled in on; coming back changes nothing.
      final proof = find.byType(AddressProofScreen);
      await tapOn(tester, stepRow('Address proof'), settle: const Duration(milliseconds: 800));
      await pumpUntil(tester, proof.hitTestable(), reason: '"Address proof" opens the proof upload');
      expect(find.descendant(of: proof, matching: find.text('Address Proof')), findsOneWidget);
      await backToChecklist(tester, proof);

      await openAndCloseMyProfile(tester, 'Profile photo', u);
      await openAndCloseMyProfile(tester, 'Address', u);
      for (final step in ['About you', 'Education', 'Profession']) {
        await openAndCloseAboutEditor(tester, step);
      }
      await pumpFor(tester, const Duration(seconds: 1));
      expect(inChecklist(find.text('33% complete')), findsOneWidget, reason: 'nothing was saved');

      await goBack(tester);
      await pumpUntilGone(tester, checklist);
      expect(inCard(find.text('Profile 33% complete')), findsOneWidget);
    },
  );

  testWidgets('saving About from the checklist raises the % on the checklist and the card at once; an admin '
      'verification shows on the next visit; at 100% the card says the profile is complete', (tester) async {
    final u = await unverifiedResident('rise');
    await givePhoto(u);
    expect((await completion(u))['percent'], 33);

    await launchApp(tester);
    await loginWithEmail(tester, u.email, u.password);
    await openProfileTab(tester);
    expect(inCard(find.text('Profile 33% complete')), findsOneWidget);
    await openChecklist(tester);

    // About you, through the real editor.
    final aboutText = 'Bakes bread for the lane on Sundays (${u.name})';
    await tapOn(tester, stepRow('About you'), settle: const Duration(milliseconds: 800));
    await pumpUntil(tester, aboutSheetTitle, reason: '"About you" opens the About editor');
    final aboutField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Tell neighbours a little about yourself',
    );
    await pumpUntil(tester, aboutField, reason: 'the editor loads');
    await typeInto(tester, aboutField, aboutText);
    await screenshot(tester, 'item5_about_editor');
    await tapOn(
      tester,
      inSheet(find.widgetWithText(ElevatedButton, 'Save')),
      settle: const Duration(milliseconds: 600),
    );
    await pumpUntilGone(tester, aboutSheetTitle, reason: 'Save closes the editor');

    await pumpUntil(
      tester,
      inChecklist(find.text('50% complete')),
      timeout: const Duration(seconds: 15),
      reason: 'the checklist refreshes on return: 3 of 6',
    );
    await expectStep(tester, 'About you', done: true);
    await expectStep(tester, 'Address proof', done: false);
    final saved = await completion(u);
    expect(saved['percent'], 50, reason: 'the server agrees');
    expect((saved['items'] as List).firstWhere((i) => i['key'] == 'about')['done'], isTrue);
    await screenshot(tester, 'item5_checklist_after_about');

    await goBack(tester);
    await pumpUntilGone(tester, checklist);
    await pumpUntil(
      tester,
      inCard(find.text('Profile 50% complete')),
      timeout: const Duration(seconds: 15),
      reason: 'the card refreshed too, without a restart',
    );
    expect(cardBar(tester), closeTo(0.5, 0.001));
    expect(inCard(find.text('Next: Upload your address proof')), findsOneWidget);
    await screenshot(tester, 'item5_card_after_about');

    // An admin verifies the member: that counts as the address proof, from the next visit.
    TestApi.ok(
      await api.send(
        'PATCH',
        '/admin/members/${u.userId}/status',
        token: await api.adminToken(),
        body: {'isVerified': true},
      ),
      'verify ${u.email}',
    );
    expect((await completion(u))['percent'], 67);
    await leaveProfileTab(tester);
    await openProfileTab(tester);
    await pumpUntil(
      tester,
      inCard(find.text('Profile 67% complete')),
      reason: 'the verification counts on the next visit',
    );
    expect(cardBar(tester), closeTo(0.67, 0.001));
    expect(inCard(find.text('Next: Add your education')), findsOneWidget);
    await screenshot(tester, 'item5_card_after_verification');

    // Education and profession saved: everything is done.
    await saveAbout(u, {
      'aboutMe': aboutText,
      'educations': [
        {'degree': 'B.Com'},
      ],
      'professions': [
        {'category': 'Accountant'},
      ],
    });
    expect((await completion(u))['percent'], 100);
    await leaveProfileTab(tester);
    await openProfileTab(tester);
    await pumpUntil(tester, inCard(find.text('Your profile is complete')), reason: 'the card at 100%');
    expect(inCard(find.textContaining('% complete')), findsNothing, reason: 'no percentage at 100%');
    expect(inCard(find.textContaining('Next:')), findsNothing, reason: 'no Next at 100%');
    expect(inCard(find.byIcon(Icons.check_circle)), findsOneWidget);
    expect(inCard(find.byIcon(Icons.chevron_right_rounded)), findsNothing);
    expect(cardBar(tester), 1.0);
    expectCardBetweenEditAndMenu(tester, 'My Profile');
    await screenshot(tester, 'item5_card_complete_resident');

    await openChecklist(tester);
    expect(inChecklist(find.text('100% complete')), findsOneWidget);
    expect(inChecklist(find.text('Your profile is complete')), findsOneWidget);
    await expectStepOrder(tester, residentSteps);
    for (final step in residentSteps) {
      await expectStep(tester, step, done: true);
    }
    await screenshot(tester, 'item5_checklist_complete_resident');
  });

  testWidgets(
    'a Home baker adds their first menu item from the checklist and the card reaches 100% without a restart',
    (tester) async {
      final s = uniqueStamp();
      final b = await api.createMember(name: 'Pbaker ${s.letters}', email: 'item5.baker.${s.digits}@example.com');
      // A Home baker (service type 1) who answered the onboarding questions ("Shop name", field 17,
      // is required) and filled in everything else but the menu.
      TestApi.ok(
        await api.send('PATCH', '/profiles/me/user-type', token: b.token, body: {'userType': 'service_provider'}),
        'make ${b.email} a provider',
      );
      TestApi.ok(
        await api.send(
          'POST',
          '/profiles/me/service-types',
          token: b.token,
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
          token: b.token,
          body: {
            'values': [
              {'fieldId': 17, 'value': 'Pbakes ${s.letters}'},
              {'fieldId': 18, 'value': 'No'},
            ],
          },
        ),
        'baker questions',
      );
      TestApi.ok(await api.send('POST', '/profiles/me/onboarding-complete', token: b.token), 'baker onboarding');
      await saveAbout(b, {
        'aboutMe': 'Cakes to order',
        'educations': [
          {'degree': 'B.Sc'},
        ],
        'professions': [
          {'category': 'Baker'},
        ],
      });
      await givePhoto(b);
      final c = await completion(b);
      expect(
        [for (final i in c['items'] as List) (i as Map)['key']],
        [
          'photo',
          'address',
          'addressProof',
          'about',
          'education',
          'profession',
          'services',
          'businessDetails',
          'menuItems',
        ],
        reason: 'a menu provider has 9 steps, with Menu items rather than Charges',
      );
      expect(c['percent'], 89, reason: '8 of 9');

      await launchApp(tester);
      await loginWithEmail(tester, b.email, b.password);
      await openProfileTab(tester);
      expect(inCard(find.text('Profile 89% complete')), findsOneWidget);
      expect(cardBar(tester), closeTo(0.89, 0.001));
      expect(inCard(find.text('Next: Add your first menu item')), findsOneWidget);
      expectCardBetweenEditAndMenu(tester, 'My Shop');
      await screenshot(tester, 'item5_card_baker');

      await openChecklist(tester);
      expect(inChecklist(find.text('89% complete')), findsOneWidget);
      await expectStepOrder(tester, [...residentSteps, 'Services', 'Business details', 'Menu items']);
      for (final step in [...residentSteps, 'Services', 'Business details']) {
        await expectStep(tester, step, done: true);
      }
      await expectStep(tester, 'Menu items', done: false, hint: 'Add your first menu item');
      expect(inChecklist(find.text('Charges')), findsNothing, reason: 'a menu provider has no Charges step');
      await screenshot(tester, 'item5_checklist_baker');

      // Menu items → Your Items → + Add Item(s) → the product form → Save.
      final items = find.byType(SpProductsScreen);
      await tapOn(tester, stepRow('Menu items'), settle: const Duration(milliseconds: 800));
      await pumpUntil(tester, items.hitTestable(), reason: '"Menu items" opens Your Items');
      await pumpUntil(
        tester,
        find.descendant(of: items, matching: find.text('No items yet — add your first product.')),
        reason: 'no items yet',
      );
      await tapOn(
        tester,
        find.descendant(of: items, matching: find.widgetWithText(ElevatedButton, '+ Add Item(s)')),
        settle: const Duration(milliseconds: 800),
      );
      final form = find.byType(AddProductScreen);
      await pumpUntil(tester, form.hitTestable(), reason: '+ Add Item(s) opens the product form');
      final product = 'Cardamom loaf ${s.letters}';
      await typeInto(
        tester,
        find.descendant(of: form, matching: find.widgetWithText(TextFormField, 'Product Name')),
        product,
      );
      await typeInto(tester, find.descendant(of: form, matching: find.widgetWithText(TextFormField, 'Price')), '450');
      await screenshot(tester, 'item5_product_form');
      await tapOn(
        tester,
        find.descendant(of: form, matching: find.widgetWithText(ElevatedButton, 'Save')),
        settle: const Duration(milliseconds: 800),
      );
      await pumpUntilGone(tester, form, reason: 'Save closes the form');
      await pumpUntil(
        tester,
        find.descendant(of: items, matching: find.text(product)),
        reason: 'the item is listed',
      );
      final done = await completion(b);
      expect(done['percent'], 100, reason: 'the server counts the first menu item');

      // Back on the checklist, then the tab: both at 100%, no restart.
      await backToChecklist(tester, items);
      // The list kept its place, at Menu items.
      await pumpUntil(
        tester,
        find.descendant(of: stepRow('Menu items'), matching: find.text('Done')),
        timeout: const Duration(seconds: 15),
        reason: 'the checklist refreshes on return',
      );
      await expectStep(tester, 'Menu items', done: true);
      await checklistToTop(tester);
      expect(inChecklist(find.text('100% complete')), findsOneWidget);
      expect(inChecklist(find.text('Your profile is complete')), findsOneWidget);
      await screenshot(tester, 'item5_checklist_baker_complete');

      await goBack(tester);
      await pumpUntilGone(tester, checklist);
      await pumpUntil(
        tester,
        inCard(find.text('Your profile is complete')),
        timeout: const Duration(seconds: 15),
        reason: 'the card refreshes on return',
      );
      expect(inCard(find.textContaining('Next:')), findsNothing);
      expect(inCard(find.byIcon(Icons.check_circle)), findsOneWidget);
      expect(cardBar(tester), 1.0);
      await screenshot(tester, 'item5_card_baker_complete');
    },
  );
}
