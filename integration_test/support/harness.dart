// On-device integration tests: they drive the real Link Local app on an iOS simulator against
// the isolated test backend, through the real UI.
//
// Needs
//  * the test backend on http://localhost:4001/api/v1: a local, seeded Postgres with
//    EXPOSE_OTP=true (codes come back as `devOtp`) and the seed admin admin@linklocal.app /
//    admin123. NEVER the production backend on port 4000: the harness refuses to start unless
//    the app points at :4001.
//  * the dart-define that points the app there.
//
// Run one file at a time (they share the simulator), from link-local-app/:
//   flutter test integration_test/bug106_login_test.dart -d <simulator-udid> \
//     --dart-define=API_BASE_URL=http://localhost:4001/api/v1
// The files: bug106_login_test.dart, bug027_guidelines_test.dart, bug104_visibility_test.dart,
// bug103_address_change_test.dart, item3_member_links_test.dart and
// item5_profile_completion_test.dart. Each takes well under two minutes after the first build.
// Optional: --dart-define=IT_SHOTS_DIR=/absolute/dir saves screenshots there (the simulator
// writes straight to the host's disk), including one of the screen whenever a wait times out.
//
// Each test seeds its own accounts, groups and posts through the API (unique emails), so the
// files can be re-run against the same database. Before the app starts, the harness wipes the
// keychain (tokens survive reinstalls there) and shared preferences, and marks the introduction
// as seen, so every test starts on a fresh Login screen.
//
// The tests never need the location; to keep the system prompt away, deny it once:
//   xcrun simctl privacy <simulator-udid> revoke location com.linklocal.app

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:link_local/app.dart';
import 'package:link_local/core/config/app_config.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/widgets/auth_header.dart';
import 'package:link_local/features/discovery/presentation/discover_screen.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/discovery/presentation/widgets/discover_cards.dart';
import 'package:link_local/features/auth/presentation/login_screen.dart';
import 'package:link_local/features/home/presentation/home_shell.dart';
import 'package:link_local/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

/// The only backend these tests may talk to.
const testApiBase = 'http://localhost:4001/api/v1';
const defaultPassword = 'Test@12345';

IntegrationTestWidgetsFlutterBinding initIntegrationTest() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  ensureTestBackend();
  return binding;
}

/// Refuses to run against anything but the isolated test backend: without the dart-define the
/// app would talk to port 4000, the production database.
void ensureTestBackend() {
  if (AppConfig.apiBaseUrl != testApiBase) {
    throw StateError('Integration tests must run against $testApiBase, but the app points at '
        '${AppConfig.apiBaseUrl}. Pass --dart-define=API_BASE_URL=$testApiBase');
  }
}

// ── Launching ─────────────────────────────────────────────────

/// Starts the real app (lib/main.dart) signed out, on the Login screen.
Future<void> launchApp(WidgetTester tester) async {
  ensureTestBackend();
  // Unmount whatever an earlier test left, so main() builds a fresh ProviderScope (it's a
  // const widget: re-running it over the old tree would keep the old state).
  await tester.pumpWidget(const SizedBox.shrink());
  await const FlutterSecureStorage().deleteAll();
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await prefs.setBool('ll_intro_seen', true);
  app.main();
  await pumpUntil(tester, find.byType(LoginScreen), reason: 'the app should open on Login');
}

ProviderContainer appContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LinkLocalApp)), listen: false);

// ── Pumping with real network calls ───────────────────────────

/// Pumps frames until [finder] matches, failing after [timeout]. Unlike pumpAndSettle it doesn't
/// hang on a spinner or a repeating animation.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
    if (DateTime.now().isAfter(end)) {
      await _failureShot(tester);
      throw TestFailure('Timed out after ${timeout.inSeconds}s waiting for $finder'
          '${reason == null ? '' : ' ($reason)'}');
    }
  }
}

/// Pumps until [finder] no longer matches.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) return;
    if (DateTime.now().isAfter(end)) {
      await _failureShot(tester);
      throw TestFailure('Timed out after ${timeout.inSeconds}s waiting for $finder to go'
          '${reason == null ? '' : ' ($reason)'}');
    }
  }
}

/// Pumps until [condition] holds (e.g. a request was made, a provider changed).
Future<void> pumpUntilTrue(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  required String reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
    if (DateTime.now().isAfter(end)) {
      await _failureShot(tester);
      throw TestFailure('Timed out after ${timeout.inSeconds}s waiting until $reason');
    }
  }
}

/// What the screen showed when a wait timed out (with IT_SHOTS_DIR).
Future<void> _failureShot(WidgetTester tester) async {
  final name = 'FAIL_${tester.testDescription.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_'
      '${DateTime.now().millisecondsSinceEpoch}';
  await screenshot(tester, name.length > 120 ? name.substring(name.length - 120) : name);
  debugPrint('on screen: ${describeScreen()}');
}

/// The screens, sheets and dialogs currently on stage, by type, for failure messages.
String describeScreen() {
  final names = find
      .byWidgetPredicate((w) => RegExp(r'(Screen|Shell|Tab|Sheet|Dialog|View)$').hasMatch(w.runtimeType.toString()))
      .evaluate()
      .map((e) => e.widget.runtimeType.toString())
      .toList();
  final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(25);
  return '$names; texts: ${texts.toList()}';
}

/// Lets animations and in-flight requests run for [duration], a frame every 50ms.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Taps [finder], scrolling it into view first when it isn't on screen, and lets the result start.
Future<void> tapOn(WidgetTester tester, Finder finder, {Duration settle = const Duration(milliseconds: 400)}) async {
  expect(finder, findsAtLeastNWidgets(1), reason: 'nothing to tap: $finder');
  await scrollIntoView(tester, finder.first);
  await tester.tap(finder.first);
  await pumpFor(tester, settle);
}

/// Scrolls [finder] to the middle of its scrollable unless it can already be tapped where it is
/// (scrolling a visible widget to the top would push headers and back buttons off screen).
Future<void> scrollIntoView(WidgetTester tester, Finder finder) async {
  if (finder.hitTestable().evaluate().isNotEmpty) return;
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Types into a text field the way the keyboard does, then closes the keyboard.
Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
  await scrollIntoView(tester, field.first);
  // Typing into the field typed into last would otherwise not reconnect the keyboard (the
  // binding skips focusing the same field twice, and hideKeyboard closed its connection).
  tester.binding.focusedEditable = null;
  await tester.enterText(field.first, text);
  await tester.pump(const Duration(milliseconds: 100));
  await hideKeyboard(tester);
}

Future<void> hideKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpFor(tester, const Duration(milliseconds: 400));
}

/// The rounded auth / address field whose placeholder is [hint].
Finder pillField(String hint) => find.byWidgetPredicate((w) => w is PillField && w.hint == hint);

/// The top screen's back control: an app bar back button, or the chevron the custom headers use.
Future<void> goBack(WidgetTester tester) async {
  final appBarBack = find.byTooltip('Back').hitTestable();
  final chevron = find.byIcon(Icons.chevron_left).hitTestable();
  // A page still loading may not show its back control yet.
  await pumpUntilTrue(tester, () => appBarBack.evaluate().isNotEmpty || chevron.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15), reason: 'a back control shows');
  await tester.tap(appBarBack.evaluate().isNotEmpty ? appBarBack.last : chevron.first);
  await pumpFor(tester, const Duration(milliseconds: 700));
}

/// One of the bottom navigation bar's items (Home · Services · Events · Groups).
Finder bottomNavItem(WidgetTester tester, String label) {
  final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  return find.byElementPredicate((e) {
    final w = e.widget;
    if (w is! Text || w.data != label) return false;
    final box = e.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    return box.localToGlobal(box.size.center(Offset.zero)).dy > screenHeight - 120;
  }, description: 'bottom nav item "$label"');
}

/// Bottom nav → Groups → search [title] → opens that group's Group Info page.
Future<void> openGroupFromGroupsTab(WidgetTester tester, String title) async {
  await tapOn(tester, bottomNavItem(tester, 'Groups'), settle: const Duration(milliseconds: 800));
  final discover = find.byType(DiscoverScreen);
  await pumpUntil(tester, discover, reason: 'the Groups tab opens Discover');
  await typeInto(tester, find.descendant(of: discover, matching: find.byType(TextField)), title);
  final card = find.widgetWithText(GroupCard, title);
  await pumpUntil(tester, card, timeout: const Duration(seconds: 40), reason: 'the group "$title" is listed');
  await tapOn(tester, card, settle: const Duration(milliseconds: 800));
  await pumpUntil(tester, find.descendant(of: find.byType(GroupProfileScreen), matching: find.text('Guidelines')),
      reason: 'the group page loads');
  await pumpFor(tester, const Duration(milliseconds: 600));
}

/// The open modal bottom sheet, and finders inside it.
Finder get bottomSheet => find.byType(BottomSheet);
Finder inSheet(Finder f) => find.descendant(of: bottomSheet, matching: f);

/// Closes the open bottom sheet by tapping the dimmed area above it.
Future<void> dismissSheet(WidgetTester tester) async {
  final top = tester.getTopLeft(bottomSheet).dy;
  await tester.tapAt(Offset(20, top / 2));
  await pumpUntilGone(tester, bottomSheet, reason: 'the sheet closes');
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// Logical screen size and the system insets (status bar, home indicator).
Size screenSize(WidgetTester tester) => tester.view.physicalSize / tester.view.devicePixelRatio;
EdgeInsets viewPadding(WidgetTester tester) =>
    EdgeInsets.fromViewPadding(tester.view.viewPadding, tester.view.devicePixelRatio);

// ── Signing in through the UI ─────────────────────────────────

/// Login → Email tab → email + password → Log in. Waits for Home when [expectHome].
Future<void> loginWithEmail(WidgetTester tester, String email, String password, {bool expectHome = true}) async {
  await openEmailTab(tester);
  await typeInto(tester, pillField('Enter your Email'), email);
  await typeInto(tester, pillField('Enter your Password'), password);
  await tapOn(tester, find.widgetWithText(ElevatedButton, 'Log in'));
  if (expectHome) {
    await pumpUntil(tester, find.byType(HomeShell), reason: 'logging in should land on Home');
    await pumpFor(tester, const Duration(milliseconds: 800));
  }
}

Future<void> openEmailTab(WidgetTester tester) async {
  await pumpUntil(tester, find.byType(LoginScreen));
  await tapOn(tester, find.text('Email'));
  await pumpUntil(tester, pillField('Enter your Email'), reason: 'the Email tab shows the email field');
}

// ── Watching what the app sends ───────────────────────────────

/// Every request the app's own Dio client makes from now on, as "METHOD /path".
class RequestLog {
  final entries = <String>[];
  bool sent(String method, String path) => entries.contains('$method $path');
  @override
  String toString() => entries.toString();
}

RequestLog recordAppRequests(WidgetTester tester) {
  final log = RequestLog();
  appContainer(tester).read(dioProvider).interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          log.entries.add('${options.method} ${options.path}');
          handler.next(options);
        },
      ));
  return log;
}

// ── Screens and pixels ────────────────────────────────────────

/// Saves a screenshot to IT_SHOTS_DIR, when given. Returns the path, or null.
///
/// What Flutter painted, rather than the simulator's own capture: once a map (a native platform
/// view) has been on screen, the native capture comes back blank for the rest of the run.
/// Native views themselves (the map) show as empty areas, and there is no status bar.
Future<String?> screenshot(WidgetTester tester, String name) async {
  const dir = String.fromEnvironment('IT_SHOTS_DIR');
  if (dir.isEmpty) return null;
  await tester.pump();
  final path = '$dir/$name.png';
  try {
    final image = await captureScreen(tester);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File(path).writeAsBytes(png!.buffer.asUint8List());
    debugPrint('screenshot: $path');
    return path;
  } catch (e) {
    debugPrint('screenshot $name failed: $e');
    return null;
  }
}

/// What Flutter last painted, in physical pixels (debug builds, which `flutter test` runs).
Future<ui.Image> captureScreen(WidgetTester tester) {
  final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
  return layer.toImage(Offset.zero & tester.view.physicalSize);
}

/// [r, g, b] of [color], to compare with [Pixels.at].
List<int> rgbOf(Color color) {
  final v = color.toARGB32();
  return [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
}

/// RGBA pixels of [image], with a lookup by logical position.
class Pixels {
  Pixels._(this._data, this._width, this._dpr);
  final ByteData _data;
  final int _width;
  final double _dpr;

  static Future<Pixels> of(WidgetTester tester) async {
    final image = await captureScreen(tester);
    final data = (await image.toByteData())!;
    final width = image.width;
    image.dispose();
    return Pixels._(data, width, tester.view.devicePixelRatio);
  }

  /// [r, g, b, a] at logical point [p].
  List<int> at(Offset p) {
    final x = (p.dx * _dpr).round();
    final y = (p.dy * _dpr).round();
    final i = (y * _width + x) * 4;
    return [_data.getUint8(i), _data.getUint8(i + 1), _data.getUint8(i + 2), _data.getUint8(i + 3)];
  }

  /// The largest difference between two colours' red, green and blue channels.
  static int distance(List<int> a, List<int> b) =>
      [for (var i = 0; i < 3; i++) (a[i] - b[i]).abs()].reduce((x, y) => x > y ? x : y);
}

// ── Seeding through the test backend's API ────────────────────

int _seq = 0;

/// A fresh suffix per call: digits for emails, letters for names (names can't hold digits).
({String digits, String letters}) uniqueStamp() {
  final digits = '${DateTime.now().millisecondsSinceEpoch}${(_seq++ % 10)}';
  final tail = digits.substring(digits.length - 7);
  final letters = tail.split('').map((d) => String.fromCharCode(97 + int.parse(d))).join();
  return (digits: digits, letters: '${letters[0].toUpperCase()}${letters.substring(1)}');
}

/// A 10-digit mobile number no other test run has used (starts with 9, like a real one).
String uniqueMobile() {
  final digits = uniqueStamp().digits;
  return '9${digits.substring(digits.length - 9)}';
}

class SeededUser {
  SeededUser({
    required this.userId,
    required this.profileId,
    required this.name,
    required this.email,
    required this.password,
    required this.token,
    this.mobile,
  });
  final int userId;
  final int profileId;
  final String name;
  final String email;
  String password;
  final String? mobile;
  String token;
}

class TestApi {
  TestApi._(this._dio);

  factory TestApi() {
    ensureTestBackend();
    return TestApi._(Dio(BaseOptions(
      baseUrl: testApiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      validateStatus: (_) => true,
    )));
  }

  final Dio _dio;
  String? _admin;

  Future<Response<dynamic>> send(String method, String path, {String? token, Object? body}) {
    assert(_dio.options.baseUrl == testApiBase);
    return _dio.request<dynamic>(path,
        data: body,
        options: Options(method: method, headers: {if (token != null) 'Authorization': 'Bearer $token'}));
  }

  static Map<String, dynamic> ok(Response<dynamic> r, String what) {
    final status = r.statusCode ?? 0;
    if (status < 200 || status >= 300) throw StateError('$what failed: $status ${r.data}');
    return r.data as Map<String, dynamic>;
  }

  Future<String> adminToken() async => _admin ??= ok(
          await send('POST', '/auth/admin/login', body: {'email': 'admin@linklocal.app', 'password': 'admin123'}),
          'admin login')['data']['accessToken'] as String;

  /// A resident with an address in Kasarvadavali (area 1, Mumbai), verified by an admin unless
  /// [verified] is false, like the members the bugs were reported on.
  Future<SeededUser> createMember({
    required String name,
    required String email,
    String? mobile,
    String apartment = 'Other Towers',
    bool verified = true,
    String password = defaultPassword,
  }) async {
    final reg = ok(
        await send('POST', '/auth/register', body: {
          'name': name,
          'email': email,
          'mobile': ?mobile,
          'password': password,
          'userType': 'resident',
        }),
        'register $email')['data'] as Map<String, dynamic>;
    final token = reg['accessToken'] as String;
    final userId = (reg['user'] as Map<String, dynamic>)['id'] as int;
    ok(
        await send('POST', '/addresses', token: token, body: {
          'cityId': 1,
          'areaId': 1,
          'apartment': apartment,
          'fullAddress': '$apartment, Kasarvadavali, Thane',
        }),
        'address for $email');
    if (verified) {
      ok(await send('PATCH', '/admin/members/$userId/status', token: await adminToken(), body: {'isVerified': true}),
          'verify $email');
    }
    final profile = ok(await send('GET', '/profiles/me', token: token), 'profile of $email')['data'];
    return SeededUser(
      userId: userId,
      profileId: profile['id'] as int,
      name: name,
      email: email,
      password: password,
      token: token,
      mobile: mobile,
    );
  }

  Future<Response<dynamic>> login(String identifier, String password) =>
      send('POST', '/auth/login', body: {'identifier': identifier, 'password': password});

  Future<Map<String, dynamic>> me(String token) async =>
      ok(await send('GET', '/auth/me', token: token), 'GET /auth/me')['data'] as Map<String, dynamic>;

  Future<Map<String, dynamic>?> myAddress(String token) async =>
      ok(await send('GET', '/addresses/me', token: token), 'GET /addresses/me')['data'] as Map<String, dynamic>?;

  /// Privacy → Profile visibility: all | area | apartment | only_me.
  Future<void> setVisibility(SeededUser u, String visibility) async =>
      ok(await send('PUT', '/profiles/me/visibility', token: u.token, body: {'profileVisibility': visibility}),
          'visibility $visibility for ${u.email}');

  Future<int> createGroup(SeededUser creator, String title, {String? description}) async => ok(
          await send('POST', '/groups', token: creator.token, body: {'title': title, 'description': ?description}),
          'create group $title')['data']['id'] as int;

  Future<void> joinGroup(SeededUser u, int groupId) async =>
      ok(await send('POST', '/groups/$groupId/join', token: u.token), '${u.email} joins group $groupId');

  Future<int> createPost(SeededUser u, String text) async => ok(
          await send('POST', '/posts', token: u.token, body: {'postType': 'share_update', 'textContent': text}),
          'post by ${u.email}')['data']['id'] as int;
}
