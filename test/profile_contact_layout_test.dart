import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/auth/auth_scope.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/business/data/business_repository.dart';
import 'package:link_local/features/discovery/data/sp_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/home/presentation/tabs/profile_tab.dart';
import 'package:link_local/features/messages/data/messages_repository.dart' show conversationsProvider;
import 'package:link_local/features/notifications/data/notifications_repository.dart';
import 'package:link_local/features/orders/data/order_models.dart';
import 'package:link_local/features/orders/data/orders_repository.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';
import 'package:link_local/features/profile/presentation/sections/basic_sections.dart';

class _Account60 extends AuthScope {
  @override
  int? build() => 60;
}

/// A signed-in resident (user 60) whose sign-in number is 9000000000.
class _Resident extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 60, userType: 'resident', name: 'Simran', mobile: '9000000000'),
      );
}

/// No orders or payments — only the profile matters here.
class _NoOrders implements OrdersRepository {
  @override
  Future<List<OrderModel>> myOrders() async => const [];
  @override
  Future<List<OrderModel>> incoming() async => const [];
  @override
  Future<DateTime> paymentsSeenAt() async => DateTime.now();

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// Their profile, with a separate public contact number set on My Profile.
final _profile = ProfileDetail.fromJson({
  'id': 6,
  'name': 'Simran',
  'user': {'id': 60, 'userType': 'resident', 'mobile': '9000000000'},
  'servicePhone': '9123456789',
});

/// The same resident as their own My Profile page loads them: the API sends the owner their
/// whole address.
final _meDetail = ServiceProviderDetail.fromJson({
  'id': 6,
  'name': 'Simran',
  'user': {'id': 60, 'userType': 'resident', 'mobile': '9000000000'},
  'servicePhone': '9123456789',
  'address': {
    'fullAddress': 'Flat 4B, Raunak Maximum City, Kasarvadavali, Thane',
    'area': {
      'areaName': 'Ghodbunder Road',
      'city': {'name': 'Mumbai'},
    },
  },
});

/// Someone else's view of a profile: the API sends only the area and city.
class _OtherMember extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 61, userType: 'resident', name: 'Ravi'),
      );
}

Future<void> _openProfileTab(WidgetTester tester, {double navBar = 0}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(bottom: navBar * 3);
  addTearDown(tester.view.reset);
  final never = Completer<Never>().future;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authScopeProvider.overrideWith(_Account60.new),
      authControllerProvider.overrideWith(_Resident.new),
      myProfileProvider.overrideWith((ref) async => _profile),
      myProviderFeaturesProvider.overrideWith((ref) => never),
      myAvailabilityProvider.overrideWith((ref) => never),
      ordersRepositoryProvider.overrideWithValue(_NoOrders()),
      conversationsProvider.overrideWith((ref) async => const []),
      unreadCountProvider.overrideWith((ref) async => 0),
      serviceProviderDetailProvider.overrideWith((ref, id) async => _meDetail),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const ProfileTab()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('BUG-062: Log Out sits above the Android navigation bar', (tester) async {
    const navBar = 48.0; // a 3-button navigation bar
    await _openProfileTab(tester, navBar: navBar);
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    final logout = tester.getRect(find.widgetWithText(OutlinedButton, 'Log Out'));
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(logout.bottom, lessThanOrEqualTo(screenHeight - navBar),
        reason: 'the button must not end up under the navigation bar');
  });

  testWidgets("BUG-068: the profile card shows the resident's public number", (tester) async {
    await _openProfileTab(tester);
    expect(find.text('9123456789'), findsOneWidget);
    expect(find.text('9000000000'), findsNothing, reason: 'the sign-in number stays private once a public one is set');
  });

  testWidgets('BUG-068: a resident can edit their Mobile number on My Profile', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final me = ServiceProviderDetail.fromJson({
      'id': 6,
      'name': 'Simran',
      'user': {'id': 60, 'userType': 'resident', 'mobile': '9000000000'},
      'servicePhone': '9123456789',
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_Resident.new),
        serviceProviderDetailProvider.overrideWith((ref, id) async => me),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ServiceProviderDetailScreen(id: 6)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Contact info:'), findsOneWidget);
    final mobileLine = find.text('Mobile: 9123456789');
    expect(mobileLine, findsOneWidget);
    // The pencil beside it opens the editor for the public number.
    final row = find.ancestor(of: mobileLine, matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)));
    await tester.pumpAndSettle();
    expect(find.text('Edit mobile number'), findsOneWidget);
  });

  testWidgets("BUG-068: a resident's Edit opens My Profile, not the Basic Info form", (tester) async {
    await _openProfileTab(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(ServiceProviderDetailScreen), findsOneWidget);
    expect(find.byType(BasicInfoScreen), findsNothing);

    // Name, birthday and gender are still a tap away: the pencil by the name.
    final nameRow = find.ancestor(of: find.text('Simran').last, matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: nameRow, matching: find.byIcon(Icons.edit_outlined)));
    await tester.pumpAndSettle();
    expect(find.byType(BasicInfoScreen), findsOneWidget);
  });

  testWidgets('My Profile shows the owner their own saved address, not just the area', (tester) async {
    await _openProfileTab(tester);
    await tester.tap(find.text('My Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Flat 4B, Raunak Maximum City, Kasarvadavali, Thane'), findsOneWidget);
    expect(find.text('Ghodbunder Road, Mumbai'), findsNothing);
  });

  testWidgets('anyone else sees only the area and city', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_OtherMember.new),
        serviceProviderDetailProvider.overrideWith((ref, id) async => _meDetail),
        myOrdersProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ServiceProviderDetailScreen(id: 6)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ghodbunder Road, Mumbai'), findsWidgets);
    expect(find.textContaining('Raunak'), findsNothing);
  });
}
