import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/data/sp_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/event_detail_screen.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/discovery/presentation/sp_menu_listing_screen.dart';
import 'package:link_local/features/orders/data/orders_repository.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

/// Records what would be dialled instead of opening the phone app.
class _Launcher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final launched = <String>[];

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _event = {'id': 21, 'title': 'testing 2.0', 'date': '2026-09-25T00:00:00.000Z', 'relation': 'hosting'};

ServiceProviderDetail _sp({bool hasMenu = false, bool blocked = false}) => ServiceProviderDetail.fromJson({
  'id': 5,
  'name': 'Aathi testing',
  'hasMenu': hasMenu,
  'isBlocked': blocked,
  'showCallButton': true,
  'publishedPhone': '9876500000',
  'user': {'id': 50},
  'events': [_event],
  'groups': [
    {'id': 10, 'title': 'Morning Walkers', 'role': 'admin'},
    {'id': 11, 'title': 'test group', 'role': 'member'},
  ],
});

/// Pages the taps lead to only need to be reached here, not loaded.
Future<void> _open(WidgetTester tester, Widget screen, ServiceProviderDetail sp) async {
  tester.view.physicalSize = const Size(1170, 8000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final never = Completer<Never>().future;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        myOrdersProvider.overrideWith((ref) async => const []),
        serviceProviderDetailProvider.overrideWith((ref, id) async => sp),
        groupDetailProvider.overrideWith((ref, id) => never),
        eventDetailProvider.overrideWith((ref, id) => never),
      ],
      child: MaterialApp(theme: AppTheme.light, home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('profile', () {
    for (final (title, id) in [('Morning Walkers', 10), ('test group', 11)]) {
      testWidgets('tapping the "$title" group opens that group', (tester) async {
        await _open(tester, const ServiceProviderDetailScreen(id: 5), _sp());
        await tester.ensureVisible(find.text(title));
        await tester.tap(find.text(title));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.widget<GroupProfileScreen>(find.byType(GroupProfileScreen)).id, id);
      });
    }

    testWidgets('tapping an event card opens that event', (tester) async {
      await _open(tester, const ServiceProviderDetailScreen(id: 5), _sp());
      await tester.ensureVisible(find.text('testing 2.0'));
      await tester.tap(find.text('testing 2.0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.widget<EventDetailScreen>(find.byType(EventDetailScreen)).id, 21);
    });
  });

  group('menu listing Call', () {
    late _Launcher launcher;
    setUp(() => UrlLauncherPlatform.instance = launcher = _Launcher());

    testWidgets("dials the provider's published number", (tester) async {
      await _open(tester, const SpMenuListingScreen(spId: 5), _sp(hasMenu: true));
      await tester.tap(find.byIcon(Icons.call_outlined));
      await tester.pump();
      expect(launcher.launched, ['tel:9876500000']);
    });

    testWidgets('a blocked provider shows no Message or Call', (tester) async {
      await _open(tester, const SpMenuListingScreen(spId: 5), _sp(hasMenu: true, blocked: true));
      expect(find.byIcon(Icons.call_outlined), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    });
  });

  test('no button or tap target in the app is left doing nothing', () {
    final dead = RegExp(r'on(Tap|Pressed): \(\) \{\}');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (dead.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: 'an empty handler looks tappable but does nothing (e.g. Refer Now, Call)');
  });
}
