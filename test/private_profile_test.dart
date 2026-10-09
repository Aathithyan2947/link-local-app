import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/discovery/presentation/user_profile_screen.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
}

/// What the server answers for a profile its owner hid from this viewer (or a real failure).
DioException _status(int code, String message) {
  final req = RequestOptions(path: '/profile');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: code, data: {'success': false, 'message': message}),
    type: DioExceptionType.badResponse,
  );
}

Future<void> _open(WidgetTester tester, Widget page, DioException error) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        authControllerProvider.overrideWith(_SignedOut.new),
        serviceProviderDetailProvider.overrideWith((ref, id) => Future.error(error)),
        publicProfileProvider.overrideWith((ref, id) => Future.error(error)),
      ],
      child: MaterialApp(theme: AppTheme.light, home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final (label, page) in [
    ('provider profile', const ServiceProviderDetailScreen(id: 5) as Widget),
    ('member profile', const UserProfileScreen(id: 8) as Widget),
  ]) {
    group(label, () {
      testWidgets('hidden by its owner: "This profile is private", no Retry', (tester) async {
        await _open(tester, page, _status(403, 'This profile is private'));
        expect(find.text('This profile is private'), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
        expect(find.text('Retry'), findsNothing, reason: "retrying won't change their setting");
        expect(find.byIcon(Icons.chevron_left), findsOneWidget, reason: 'there is still a way back');
      });

      testWidgets('a real failure still offers Retry', (tester) async {
        await _open(tester, page, _status(500, 'Internal server error'));
        expect(find.text('This profile is private'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);
      });
    });
  }
}
