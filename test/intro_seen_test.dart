import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/storage/intro_seen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<bool?> _settled(ProviderContainer c) async {
  c.listen(introSeenProvider, (_, _) {});
  for (var i = 0; i < 20 && c.read(introSeenProvider) == null; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return c.read(introSeenProvider);
}

void main() {
  test('a fresh install has not seen the introduction', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await _settled(c), isFalse);
  });

  test('once seen, it stays seen across restarts (and logouts)', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    await _settled(first);
    await first.read(introSeenProvider.notifier).markSeen();
    first.dispose();

    final relaunched = ProviderContainer(); // same storage, new app session
    addTearDown(relaunched.dispose);
    expect(await _settled(relaunched), isTrue);
  });
}
