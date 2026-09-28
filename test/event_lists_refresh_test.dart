import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/discovery/event_lists_refresh.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/data/home_repository.dart';

class _FakeHomeRepo implements HomeRepository {
  var fetches = 0;
  @override
  Future<HomeFeed> getHome({String scope = 'city', int? areaId}) async {
    fetches++;
    return HomeFeed.fromJson({'workshops': {'total': fetches, 'items': []}});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  testWidgets('creating an event refreshes the Home feed without a pull-to-refresh', (tester) async {
    final repo = _FakeHomeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [homeRepositoryProvider.overrideWithValue(repo), dioProvider.overrideWithValue(Dio())],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            final feed = ref.watch(homeFeedProvider);
            return Column(children: [
              Text('workshops: ${feed.value?.workshops.total ?? '-'}'),
              TextButton(onPressed: ref.invalidateEventLists, child: const Text('event created')),
            ]);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('workshops: 1'), findsOneWidget);

    await tester.tap(find.text('event created'));
    await tester.pumpAndSettle();
    expect(repo.fetches, 2);
    expect(find.text('workshops: 2'), findsOneWidget);
  });
}
