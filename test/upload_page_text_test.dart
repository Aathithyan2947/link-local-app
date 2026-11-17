import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/address/presentation/address_verify_screen.dart';
import 'package:link_local/features/reference/reference_repository.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [referralSourcesProvider.overrideWith((ref) async => const [])],
    child: MaterialApp(theme: AppTheme.light, home: const AddressVerifyScreen()),
  ));
  await tester.pumpAndSettle();
}

TextStyle _style(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!;

void main() {
  group('BUG-076: the upload page text follows the Figma (Sign Up 6)', () {
    testWidgets('subtitle, upload label and referral heading use the Figma sizes and Medium weight',
        (tester) async {
      await _pump(tester);

      final subtitle = _style(tester, 'This keeps our community authentic and safe');
      expect(subtitle.fontSize, 16);
      expect(subtitle.fontWeight, FontWeight.w500);

      final upload = _style(tester, 'Upload your address proof');
      expect(upload.fontSize, 14);
      expect(upload.fontWeight, FontWeight.w500);

      final referral = _style(tester, 'Got a referral code?');
      expect(referral.fontSize, 16);
      expect(referral.fontWeight, FontWeight.w500);

      final helper = _style(tester, 'This will help us verify your profile faster');
      expect(helper.fontSize, 12);
      expect(helper.fontWeight, FontWeight.w500);
    });

    testWidgets('the button reads "Submit now"', (tester) async {
      await _pump(tester);
      expect(find.widgetWithText(ElevatedButton, 'Submit now'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });
  });
}
