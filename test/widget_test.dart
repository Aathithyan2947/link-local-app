import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/widgets/primary_button.dart';

void main() {
  testWidgets('PrimaryButton renders its label and fires onPressed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryButton(label: 'Get Started', onPressed: () => tapped = true),
        ),
      ),
    );

    expect(find.text('Get Started'), findsOneWidget);
    await tester.tap(find.byType(PrimaryButton));
    expect(tapped, isTrue);
  });

  testWidgets('PrimaryButton shows a spinner when loading', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PrimaryButton(label: 'Loading', loading: true)),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading'), findsNothing);
  });
}
