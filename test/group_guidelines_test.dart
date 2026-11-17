import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_colors.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/core/validation/content_limits.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/discovery/data/group_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/group_profile_screen.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';

class _Member extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 5, userType: 'resident', name: 'Asha', hasAddress: true),
      );
}

class _Server implements DiscoveryRepository {
  @override
  Future<GroupMembers> groupMembers(int id) async =>
      GroupMembers(const [GroupMember(userId: 5, name: 'Asha', isCreator: true)]);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// The longest description the create form allows, as numbered rules.
final _longGuidelines = () {
  final b = StringBuffer();
  for (var i = 1; b.length < ContentLimits.description - 60; i++) {
    b.write('$i. Be kind, keep posts about running and share route changes early.\n');
  }
  return b.toString().substring(0, ContentLimits.description - 60);
}();

/// Phone-sized by default, with a home indicator at the bottom.
Future<void> _open(WidgetTester tester,
    {String? description, bool phone = true, bool member = true, double dpr = 3}) async {
  if (phone) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  } else {
    tester.view.physicalSize = Size(600 * dpr, 4000);
  }
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(_Member.new),
      discoveryRepositoryProvider.overrideWithValue(_Server()),
      groupDetailProvider.overrideWith((ref, id) async => GroupDetail.fromJson({
            'id': 3,
            'title': 'Morning Runners',
            'description': description,
            'creator': {
              'profile': {'name': 'Asha'},
            },
            '_count': {'members': 1},
            'isCreator': member,
            if (member) 'myMembership': {'status': 'joined'},
          })),
      homeFeedProvider.overrideWith((ref) => Completer<HomeFeed>().future),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const GroupProfileScreen(id: 3)),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester, String action) async {
  await tester.tap(find.text(action).first);
  await tester.pumpAndSettle();
}

Finder get _sheet => find.byType(BottomSheet);
Finder _inSheet(Finder f) => find.descendant(of: _sheet, matching: f);

/// The white action card under the green header.
Finder get _card => find.ancestor(
      of: find.text('Add Person'),
      matching: find.byWidgetPredicate((w) =>
          w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).boxShadow != null),
    );

void main() {
  group('BUG-027: group Guidelines sheet', () {
    testWidgets('a long description scrolls inside the sheet instead of overflowing it', (tester) async {
      await _open(tester, description: _longGuidelines);
      await _openSheet(tester, 'Guidelines');

      expect(tester.takeException(), isNull);
      expect(_inSheet(find.text(_longGuidelines.trim())), findsOneWidget);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(tester.getSize(_sheet).height, lessThan(screen.height * 0.9));
      expect(tester.getTopLeft(_sheet).dy, greaterThan(47), reason: 'clear of the status bar');

      final scroll = _inSheet(find.byType(Scrollable));
      final position = tester.state<ScrollableState>(scroll).position;
      expect(position.maxScrollExtent, greaterThan(0));

      final titleTop = tester.getTopLeft(_inSheet(find.text('Guidelines'))).dy;
      await tester.drag(scroll, const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(position.pixels, position.maxScrollExtent, reason: 'scrolls to the last rule');
      expect(tester.getTopLeft(_inSheet(find.text('Guidelines'))).dy, titleTop, reason: 'the title stays put');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the content clears the home indicator', (tester) async {
      await _open(tester, description: _longGuidelines);
      await _openSheet(tester, 'Guidelines');

      expect(_inSheet(find.byType(SafeArea)), findsOneWidget);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(tester.getRect(_inSheet(find.byType(Scrollable))).bottom, lessThanOrEqualTo(screen.height - 34));
    });

    testWidgets('no description shows an empty state', (tester) async {
      await _open(tester, phone: false);
      await _openSheet(tester, 'Guidelines');
      expect(_inSheet(find.text('No guidelines yet.')), findsOneWidget);
    });

    testWidgets('a blank description shows the empty state too', (tester) async {
      await _open(tester, description: '  \n  ', phone: false);
      await _openSheet(tester, 'Guidelines');
      expect(_inSheet(find.text('No guidelines yet.')), findsOneWidget);
    });

    // Members used to open a sheet to line up with; it's a page now (BUG-082).
    testWidgets('the title lines up with the guidelines text', (tester) async {
      await _open(tester, description: 'Be kind.', phone: false);
      await _openSheet(tester, 'Guidelines');
      final guidelinesInset =
          tester.getTopLeft(_inSheet(find.text('Guidelines'))).dx - tester.getTopLeft(_sheet).dx;
      expect(_inSheet(find.text('Be kind.')), findsOneWidget);
      expect(tester.getTopLeft(_inSheet(find.text('Be kind.'))).dx - tester.getTopLeft(_sheet).dx,
          guidelinesInset);
    });
  });

  group('BUG-027: group header action card', () {
    testWidgets('leaves no empty gap below it', (tester) async {
      await _open(tester, phone: false);
      final cardBottom = tester.getRect(_card).bottom;
      final post = find.ancestor(of: find.text('Post'), matching: find.byWidgetPredicate((w) => w is TextButton));
      // Only the discussions section's own 12px top padding sits between them.
      expect(tester.getTopLeft(post).dy - cardBottom, 12);
    });

    testWidgets('a non-member\'s Join button sits the same 12px below it', (tester) async {
      await _open(tester, phone: false, member: false);
      final join = find.widgetWithText(ElevatedButton, 'Join Group');
      expect(tester.getTopLeft(join).dy - tester.getRect(_card).bottom, 12);
    });

    testWidgets('still overlaps the green header', (tester) async {
      await _open(tester, phone: false);
      final headerTextBottom = tester.getBottomLeft(find.text('Created by Asha')).dy;
      expect(tester.getRect(_card).top - headerTextBottom, 12);
      // The green, whichever widget paints it, runs 22px down behind the card.
      final green = find.byWidgetPredicate((w) =>
          (w is ColoredBox && w.color == AppColors.primary) ||
          (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.primary));
      final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final greenBottom = green
          .evaluate()
          .map((e) => e.renderObject! as RenderBox)
          .map((box) => box.localToGlobal(Offset.zero) & box.size)
          .where((r) => r.width == width)
          .map((r) => r.bottom)
          .reduce((a, b) => a > b ? a : b);
      expect(greenBottom - tester.getRect(_card).top, 22);
    });

    testWidgets('leaves no pale hairline across the green beside it', (tester) async {
      // 2.75 puts the edge between the header and the green behind the card on a half pixel.
      const dpr = 2.75;
      await _open(tester, phone: false, dpr: dpr);
      final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      final image = (await tester.runAsync(() => layer.toImage(Offset.zero & tester.view.physicalSize)))!;
      addTearDown(image.dispose);
      final pixels = (await tester.runAsync(image.toByteData))!;
      final rgba = (AppColors.primary.toARGB32() & 0xFFFFFF) << 8 | 0xFF;
      // Every physical row between the header text and the bottom of the green, left of the card.
      final from = (tester.getBottomLeft(find.text('Created by Asha')).dy * dpr).ceil();
      final to = ((tester.getRect(_card).top + 22) * dpr).floor();
      const x = (8 * dpr) ~/ 1;
      for (var y = from; y < to; y++) {
        expect(pixels.getUint32((y * image.width + x) * 4).toRadixString(16), rgba.toRadixString(16),
            reason: 'row $y');
      }
    });

    testWidgets('clips the action ripples to its rounded corners', (tester) async {
      await _open(tester, phone: false);
      final ink = find.ancestor(of: find.text('Guidelines'), matching: find.byType(InkWell));
      final material = tester.widget<Material>(find.ancestor(of: ink, matching: find.byType(Material)).first);
      expect(material.clipBehavior, isNot(Clip.none));
      expect(material.borderRadius, BorderRadius.circular(16));
      final painted = find.descendant(of: _card, matching: find.byType(DecoratedBox)).first;
      expect(tester.getRect(find.byWidget(material)), tester.getRect(painted),
          reason: 'the ripple can fill the whole card');
    });
  });
}
