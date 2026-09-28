import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/features/address/data/address_models.dart';
import 'package:link_local/features/address/data/address_repository.dart';
import 'package:link_local/features/address/presentation/widgets/place_search_field.dart';

class _FakeAddressRepo implements AddressRepository {
  int? cityAsked;

  @override
  Future<List<PlaceSuggestion>> autocomplete(String q, {required String sessionToken, required int cityId}) async {
    cityAsked = cityId;
    return const [PlaceSuggestion(placeId: 'P1', primaryText: 'Hiranandani Meadows', secondaryText: 'Thane')];
  }

  @override
  Future<PlaceAddress?> placeDetails(String placeId, {String? sessionToken}) async => PlaceAddress.fromJson(
      {'latitude': 19.23, 'longitude': 72.97, 'googlePlaceId': placeId, 'isPrecise': true, 'isNamed': true});

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakeAddressRepo repo;
  late TextEditingController ctrl;
  late List<PickedPlace?> reported;

  Future<void> pump(WidgetTester tester) async {
    repo = _FakeAddressRepo();
    ctrl = TextEditingController();
    reported = [];
    await tester.pumpWidget(ProviderScope(
      overrides: [addressRepositoryProvider.overrideWithValue(repo), dioProvider.overrideWithValue(Dio())],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(children: [PlaceSearchField(controller: ctrl, cityId: 1, onChanged: reported.add)]),
        ),
      ),
    ));
  }

  testWidgets('suggests places in the host city, picking fills text and position', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField), 'Hiran');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repo.cityAsked, 1);
    expect(find.text('Use "Hiran" as typed'), findsOneWidget);

    await tester.tap(find.text('Hiranandani Meadows'));
    await tester.pumpAndSettle();
    expect(ctrl.text, 'Hiranandani Meadows, Thane');
    expect(reported.last?.latitude, 19.23);
    expect(reported.last?.googlePlaceId, 'P1');
    expect(find.text('Hiranandani Meadows'), findsNothing, reason: 'list closes after picking');
  });

  testWidgets('editing after a pick drops the stale position', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField), 'Hiran');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hiranandani Meadows'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Hiranandani Meadows, Tower B terrace');
    await tester.pump();
    expect(reported.last, isNull);
  });

  testWidgets('"use as typed" keeps the text with no position', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField), 'Clubhouse hall');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use "Clubhouse hall" as typed'));
    await tester.pumpAndSettle();
    expect(ctrl.text, 'Clubhouse hall');
    expect(reported.last, isNull);
  });
}
