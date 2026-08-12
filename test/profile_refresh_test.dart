@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the fix for "I save an edit and the profile keeps showing the old data".
///
/// The screen used to swap to a full-screen spinner while refetching, which disposed the
/// subtree holding the pencils — and with it the `ref` the open editor was going to refresh
/// with, so the refresh silently did nothing. Refreshing is now owned by the screen itself
/// via RouteAware.didPopNext(), which can't be disposed out from under an editor.
void main() {
  const screen = 'lib/features/discovery/presentation/service_provider_detail_screen.dart';

  test('the profile keeps its content while refetching', () {
    final source = File(screen).readAsStringSync();
    expect(source.contains('skipLoadingOnReload: true'), isTrue,
        reason: 'a reload must not replace the page with a spinner — that disposes the pencils');
  });

  test('the screen refreshes itself when an editor closes', () {
    final source = File(screen).readAsStringSync();
    expect(source.contains('with RouteAware'), isTrue);
    expect(source.contains('void didPopNext()'), isTrue);
    expect(source.contains('appRouteObserver.subscribe'), isTrue);
    expect(source.contains('appRouteObserver.unsubscribe'), isTrue,
        reason: 'an un-unsubscribed RouteAware leaks the observer entry');
  });

  test('the observer is registered on the router, or didPopNext never fires', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();
    expect(source.contains('final appRouteObserver = RouteObserver<ModalRoute<void>>()'), isTrue);
    expect(source.contains('observers: [appRouteObserver]'), isTrue);
  });

  test('the editor no longer invalidates the profile mid-edit', () {
    final source = File('lib/features/services/presentation/category_fields_form_screen.dart').readAsStringSync();
    final save = source.substring(source.indexOf('Future<void> _save() async {'));
    final body = save.substring(0, save.indexOf('String get _buttonLabel'));
    expect(
      body.contains('invalidate(serviceProviderDetailProvider)'),
      isFalse,
      reason: 'invalidating from _save() puts the profile into its loading state while the '
          'editor is still open, which is what disposed the subtree mid-interaction',
    );
  });

  test('the onboarding chain still drops the cached profile on its final hop', () {
    final source = File('lib/features/services/presentation/category_fields_form_screen.dart').readAsStringSync();
    final chain = source.substring(source.indexOf('Future<void> pushOnboardingStep('));
    // That hop pushes a NEW profile route rather than returning to one, so didPopNext can't
    // cover it.
    expect(chain.contains('invalidate(serviceProviderDetailProvider)'), isTrue);
  });
}
