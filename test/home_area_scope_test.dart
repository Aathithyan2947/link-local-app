import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/presentation/widgets/area_picker_sheet.dart';
import 'package:link_local/features/services/data/service_profile_repository.dart';

class _FakeServiceRepo implements ServiceProfileRepository {
  @override
  Future<List<SelectedArea>> searchAreas({String? q, int? cityId}) async =>
      const [SelectedArea(id: 7, areaName: 'Pai Nagar'), SelectedArea(id: 8, areaName: 'Gaimukh')];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

ServiceProviderItem _sp(Map<String, dynamic> extra) =>
    ServiceProviderItem.fromJson({'id': 1, 'name': 'X', ...extra});

void main() {
  group('card location line', () {
    test('area, city and distance', () {
      expect(_sp({'areaName': 'Pai Nagar', 'cityName': 'Mumbai', 'distanceLabel': '1.5 km'}).locationLine,
          'Pai Nagar, Mumbai | 1.5 km');
    });
    test('no distance known', () {
      expect(_sp({'areaName': 'Pai Nagar', 'cityName': 'Mumbai'}).locationLine, 'Pai Nagar, Mumbai');
    });
    test('city only', () {
      expect(_sp({'cityName': 'Mumbai'}).locationLine, 'Mumbai');
    });
    test('nothing known — no stray separator', () {
      expect(_sp({}).locationLine, '');
    });
  });

  Future<AreaScopeChoice?> pick(WidgetTester tester, String row, {int? selected, bool whole = false}) async {
    AreaScopeChoice? result;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        serviceProfileRepositoryProvider.overrideWithValue(_FakeServiceRepo()),
        dioProvider.overrideWithValue(Dio()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showAreaScopeSheet(context,
                cityId: 1, cityName: 'Mumbai', selectedAreaId: selected, wholeCitySelected: whole),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('"All of Mumbai" returns the whole city', (tester) async {
    final choice = await pick(tester, 'All of Mumbai', selected: 7);
    expect(choice, isNotNull);
    expect(choice!.isWholeCity, isTrue);
  });

  testWidgets('an area row returns that area', (tester) async {
    final choice = await pick(tester, 'Gaimukh', whole: true);
    expect(choice!.area!.id, 8);
  });
}
