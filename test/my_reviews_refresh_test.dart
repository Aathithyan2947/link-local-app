@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BUG-098: Profile → My Reviews is cached for the whole session, so a review submitted after
/// it was first opened never showed up there. Every screen that submits a review must drop
/// that cache.
void main() {
  test('every screen that submits a review refreshes My Reviews', () {
    final submit = RegExp(r'\.(submitReview|rateEvent|rateGroup)\(');
    final offenders = <String>[];
    var submitters = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('discovery_repository.dart')) continue;
      final src = f.readAsStringSync();
      if (!submit.hasMatch(src)) continue;
      submitters++;
      if (!src.contains('invalidate(myReviewsProvider)')) offenders.add(f.path);
    }
    expect(submitters, greaterThan(0), reason: 'the scan should find the review screens');
    expect(offenders, isEmpty, reason: 'these submit a review without refreshing My Reviews');
  });
}
