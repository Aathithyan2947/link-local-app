import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/text/plural.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/discover_screen.dart';
import 'package:link_local/features/discovery/presentation/widgets/discover_cards.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

GroupItem _group(int members) => GroupItem.fromJson({
  'id': 1,
  'title': 'test group',
  '_count': {'members': members},
});

void main() {
  group('BUG-054: "1 Member", not "1 Members"', () {
    test('countLabel', () {
      expect(countLabel(0, 'Member'), '0 Members');
      expect(countLabel(1, 'Member'), '1 Member');
      expect(countLabel(2, 'Member'), '2 Members');
      expect(countLabel(1, 'Service Provider'), '1 Service Provider');
      expect(countLabel(3, 'item'), '3 items');
    });

    for (final (n, text) in [(1, '1 Member'), (2, '2 Members')]) {
      testWidgets('a group card with $n shows "$text"', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: GroupCard(group: _group(n), onTap: () {})),
        ));
        expect(find.text(text), findsOneWidget);
      });
    }
  });

  group('BUG-055: the four tabs share one size', () {
    Future<void> openAt(WidgetTester tester, double logicalWidth) async {
      tester.view.physicalSize = Size(logicalWidth * 3, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final never = Completer<Never>().future;
      Section<T> section<T>(int total) => Section<T>(total: total, items: const []);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(Dio()),
            authControllerProvider.overrideWith(_SignedOut.new),
            homeFeedProvider.overrideWith((ref) => never),
            // Several-digit counts, as on a busy city.
            discoverEventsProvider.overrideWith((ref) async => section<WorkshopItem>(128)),
            discoverServiceProvidersProvider.overrideWith((ref) async => section<ServiceProviderItem>(1030)),
            discoverGroupsProvider.overrideWith((ref) async => section<GroupItem>(215)),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const DiscoverScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// How large each tab label is drawn, relative to its unscaled layout height.
    Map<String, double> scales(WidgetTester tester) => {
      for (final label in ['All', 'Events', 'Service Providers', 'Groups'])
        label: tester.getRect(find.text(label).last).height /
            tester.renderObject<RenderBox>(find.text(label).last).size.height,
    };

    testWidgets('on a narrow phone they shrink, but all by the same amount', (tester) async {
      await openAt(tester, 320);
      final s = scales(tester);
      expect(s['Service Providers']!, lessThan(1), reason: 'too wide to fit unscaled at 320pt');
      for (final v in s.values) {
        expect(v, closeTo(s['All']!, 0.02), reason: 'every tab label at the same size: $s');
      }
    });

    // Test fonts draw every letter as a wide square, so the row only fits unscaled on a wide
    // screen here (on a phone, in Poppins, it fits at normal widths).
    testWidgets('when the row fits, nothing shrinks', (tester) async {
      await openAt(tester, 800);
      for (final v in scales(tester).values) {
        expect(v, closeTo(1, 0.001));
      }
    });
  });
}
