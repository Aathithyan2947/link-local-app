import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/network/dio_client.dart';
import 'package:link_local/core/theme/app_theme.dart';
import 'package:link_local/features/auth/application/auth_controller.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/business/data/business_repository.dart';
import 'package:link_local/features/discovery/data/sp_detail_models.dart';
import 'package:link_local/features/discovery/discovery_repository.dart';
import 'package:link_local/features/discovery/presentation/service_provider_detail_screen.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/home/presentation/widgets/service_icons.dart';
import 'package:link_local/features/orders/data/orders_repository.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/profile/data/profile_repository.dart';
import 'package:link_local/features/reference/reference_models.dart';
import 'package:link_local/features/reference/reference_repository.dart';
import 'package:link_local/features/services/data/field_merge.dart';
import 'package:link_local/features/services/data/service_profile_repository.dart';
import 'package:link_local/features/services/presentation/category_fields_form_screen.dart';
import 'package:link_local/features/services/presentation/service_category_screen.dart';

/// Provider 70 (profile 7): offers Yoga, and typed in "Pottery classes", still awaiting approval.
class _Provider extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 70, userType: 'service_provider', name: 'Asha', hasAddress: true, hasServices: true),
      );
  @override
  Future<void> refreshUser() async {}
}

class _Visitor extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 61, userType: 'resident', name: 'Ravi'),
      );
}

Map<String, dynamic> _serviceType(int id, String name, {bool active = true}) => {
      'id': id + 100,
      'subcategoryId': id,
      'subcategory': {'id': id, 'name': name, 'isActive': active},
    };

final _myProfile = ProfileDetail.fromJson({
  'id': 7,
  'name': 'Asha',
  'user': {'id': 70, 'userType': 'service_provider'},
  'serviceTypes': [_serviceType(11, 'Yoga instructor'), _serviceType(31, 'Pottery classes', active: false)],
});

const _categories = [
  ServiceCategory(id: 1, name: 'Fitness', subcategories: [
    ServiceSubcategory(id: 11, name: 'Yoga instructor', categoryId: 1),
    ServiceSubcategory(id: 12, name: 'Zumba trainer', categoryId: 1),
  ]),
  ServiceCategory(id: 2, name: 'Beauticians', subcategories: [
    ServiceSubcategory(id: 21, name: 'Hair stylist', categoryId: 2),
  ]),
];

CustomField _field(
  int id,
  int service,
  String category,
  String name, {
  String type = 'text',
  bool required = false,
  String? value,
  int? dependsOn,
  String? dependsOnValue,
}) =>
    CustomField(
      fieldId: id,
      subcategoryId: service,
      subcategoryName: {11: 'Yoga instructor', 21: 'Hair stylist'}[service] ?? 'Service $service',
      category: category,
      fieldName: name,
      fieldType: type,
      isRequired: required,
      value: value,
      dependsOnFieldId: dependsOn,
      dependsOnValue: dependsOnValue,
    );

/// Records what the provider saved; [fields] are their setup questions and answers.
class _Services implements ServiceProfileRepository {
  _Services([this.fields = const []]);
  List<CustomField> fields;
  final savedServices = <List<int>>[];
  final savedAnswers = <List<Map<String, dynamic>>>[];

  @override
  Future<void> saveServiceTypes(List<int> subcategoryIds, {List<Map<String, dynamic>> customServices = const []}) async =>
      savedServices.add(subcategoryIds);
  @override
  Future<List<CustomField>> getCustomFields() async => fields;
  @override
  Future<void> saveCustomFields(List<Map<String, dynamic>> values) async => savedAnswers.add(values);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<void> _pump(WidgetTester tester, _Services services, Widget screen, {AuthController Function()? auth}) async {
  // Wide: the test font is wider than Poppins.
  tester.view.physicalSize = const Size(1800, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()),
      authControllerProvider.overrideWith(auth ?? _Provider.new),
      myProfileProvider.overrideWith((ref) async => _myProfile),
      serviceCategoriesProvider.overrideWith((ref) async => _categories),
      serviceProfileRepositoryProvider.overrideWithValue(services),
      myProviderFeaturesProvider.overrideWith((ref) async => (hasMenu: false, hasDateBooking: false)),
      myAvailabilityProvider.overrideWith((ref) => Completer<Never>().future),
      myOrdersProvider.overrideWith((ref) async => const []),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _row(String name) => find.ancestor(of: find.text(name), matching: find.byType(ListTile));
bool _ticked(WidgetTester tester, String name) =>
    find.descendant(of: _row(name), matching: find.byIcon(Icons.check_circle)).evaluate().isNotEmpty;

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  group('BUG-096: My Services', () {
    testWidgets('opens with the current services ticked, keeps a pending one, and saves a change', (tester) async {
      final services = _Services();
      await _pump(tester, services, const ServiceCategoryScreen(editing: true));

      expect(find.text('My Services'), findsOneWidget);
      expect(_ticked(tester, 'Yoga instructor'), isTrue);
      expect(_ticked(tester, 'Zumba trainer'), isFalse);
      expect(find.text('WAITING FOR APPROVAL'), findsOneWidget,
          reason: 'a typed-in service is not in the approved list, so it gets its own row');
      expect(_ticked(tester, 'Pottery classes'), isTrue);

      await tester.tap(find.text('Hair stylist'));
      await tester.pump();
      await _save(tester);

      expect(services.savedServices.single, unorderedEquals([11, 21, 31]));
      expect(find.text('Services updated'), findsOneWidget);
      expect(find.byType(ServiceCategoryScreen), findsNothing, reason: 'back where My Services was opened');
    });

    testWidgets('unticking services removes them; nothing ticked is not saved', (tester) async {
      final services = _Services();
      await _pump(tester, services, const ServiceCategoryScreen(editing: true));

      await tester.tap(find.text('Pottery classes'));
      await tester.pump();
      expect(_ticked(tester, 'Pottery classes'), isFalse);
      await tester.tap(find.text('Yoga instructor'));
      await tester.pump();
      await _save(tester);
      expect(find.text('Select at least one service you offer'), findsOneWidget);
      expect(services.savedServices, isEmpty);

      await tester.tap(find.text('Zumba trainer'));
      await tester.pump();
      await _save(tester);
      expect(services.savedServices.single, [12]);
    });

    testWidgets('a new service with setup questions offers to answer them now', (tester) async {
      final services = _Services([
        _field(1, 11, 'payment', 'Fee per session', value: '500'),
        _field(2, 21, 'payment', 'Fee per visit', type: 'number', required: true),
      ]);
      await _pump(tester, services, const ServiceCategoryScreen(editing: true));
      await tester.tap(find.text('Hair stylist'));
      await tester.pump();
      await _save(tester);

      expect(find.text('Set up your new services?'), findsOneWidget);
      await tester.tap(find.text('Set up now'));
      await tester.pumpAndSettle();
      expect(find.byType(CategoryFieldsFormScreen), findsOneWidget);
      expect(find.text('Payment & Fee'), findsOneWidget);
    });
  });

  group('BUG-099: questions several services share are asked once', () {
    test('merges copies in Basic Details, Travel and Delivery; Payment stays per service', () {
      final merged = mergeSharedFields([
        _field(1, 11, 'basic_details', 'Your Name', value: 'Asha'),
        _field(2, 11, 'basic_details', 'Years of experience', type: 'number'),
        _field(3, 11, 'payment', 'Fee'),
        _field(4, 21, 'basic_details', 'your  name:', required: true),
        _field(5, 21, 'basic_details', 'Years of experience', type: 'number', value: '6'),
        _field(6, 21, 'basic_details', 'Languages'),
        _field(7, 21, 'payment', 'Fee'),
        _field(8, 21, 'basic_details', 'Years of experience', type: 'dropdown'),
      ]);

      expect(merged.fields.map((f) => f.fieldId), [1, 2, 3, 6, 7, 8],
          reason: 'a different type is a different question');
      final name = merged.fields.first;
      expect(name.isRequired, isTrue, reason: 'required when any service requires it');
      expect(name.value, 'Asha');
      expect(merged.fields[1].value, '6', reason: 'the first saved answer among the copies');
      expect(merged.membersOf(1), [1, 4]);
      expect(merged.membersOf(2), [2, 5]);
      expect(merged.membersOf(3), [3]);
      expect(merged.shownIdOf(5), 2);
    });

    test('a question that depends on a merged one follows it', () {
      final merged = mergeSharedFields([
        _field(10, 11, 'travel', 'Willing to travel', type: 'boolean'),
        _field(11, 11, 'travel', 'Distance', type: 'number', dependsOn: 10, dependsOnValue: 'true'),
        _field(12, 21, 'travel', 'Willing to travel', type: 'boolean'),
        _field(13, 21, 'travel', 'Distance', type: 'number', dependsOn: 12, dependsOnValue: 'true'),
        _field(14, 21, 'travel', 'Areas', type: 'pincode', dependsOn: 12, dependsOnValue: 'true'),
      ]);
      expect(merged.fields.map((f) => f.fieldId), [10, 11, 14]);
      expect(merged.membersOf(11), [11, 13]);
      expect(merged.fields.last.dependsOnFieldId, 10, reason: "service B's copy was merged into A's");
    });

    testWidgets('the Basic Details form asks once and saves the answer for every service', (tester) async {
      final services = _Services([
        _field(1, 11, 'basic_details', 'Years of experience', type: 'number', required: true),
        _field(2, 11, 'basic_details', 'Favourite subject'),
        _field(4, 21, 'basic_details', 'Years of experience', type: 'number'),
        _field(5, 21, 'basic_details', 'Languages'),
      ]);
      await _pump(tester, services,
          const CategoryFieldsFormScreen(category: 'basic_details', categoryLabel: 'Basic Details'));

      expect(find.byType(TextField), findsNWidgets(3), reason: 'experience once, plus each service\'s own question');
      await tester.enterText(find.byType(TextField).first, '6');
      await tester.enterText(find.byType(TextField).last, 'Hindi');
      await _save(tester);

      final saved = {for (final v in services.savedAnswers.single) v['fieldId']: v['value']};
      expect(saved, {1: '6', 2: '', 4: '6', 5: 'Hindi'});
    });

    testWidgets('the Payment form keeps each service apart, under its name', (tester) async {
      final services = _Services([
        _field(3, 11, 'payment', 'Fee', value: '500'),
        _field(7, 21, 'payment', 'Fee', value: '300'),
      ]);
      await _pump(tester, services, const CategoryFieldsFormScreen(category: 'payment', categoryLabel: 'Payment & Fee'));
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Yoga instructor'), findsOneWidget);
      expect(find.text('Hair stylist'), findsOneWidget);
    });

    test("the public profile shows a shared answer once", () {
      final sp = ServiceProviderDetail.fromJson({
        'id': 7,
        'name': 'Asha',
        'customFields': [
          {'fieldId': 1, 'subcategoryId': 11, 'subcategoryName': 'Yoga instructor', 'category': 'delivery', 'fieldName': 'Delivery charge', 'fieldType': 'number', 'value': '40'},
          {'fieldId': 4, 'subcategoryId': 21, 'subcategoryName': 'Hair stylist', 'category': 'delivery', 'fieldName': 'Delivery charge', 'fieldType': 'number', 'value': '40'},
          {'fieldId': 3, 'subcategoryId': 11, 'subcategoryName': 'Yoga instructor', 'category': 'payment', 'fieldName': 'Fee', 'fieldType': 'number', 'value': '500'},
          {'fieldId': 7, 'subcategoryId': 21, 'subcategoryName': 'Hair stylist', 'category': 'payment', 'fieldName': 'Fee', 'fieldType': 'number', 'value': '300'},
        ],
      });
      expect(sp.customFields.map((f) => f.fieldId), [1, 3, 7]);
    });
  });

  group('BUG-099: every service shows, not just the first', () {
    final detailJson = {
      'id': 7,
      'name': 'Asha',
      'user': {'id': 70, 'userType': 'service_provider'},
      'serviceTypes': [
        _serviceType(11, 'Yoga instructor'),
        _serviceType(21, 'Hair stylist'),
        _serviceType(31, 'Pottery classes', active: false),
      ],
    };

    Future<void> openDetail(WidgetTester tester, AuthController Function() auth) async {
      final sp = ServiceProviderDetail.fromJson(detailJson);
      tester.view.physicalSize = const Size(1800, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(Dio()),
          authControllerProvider.overrideWith(auth),
          serviceProviderDetailProvider.overrideWith((ref, id) async => sp),
          myProfileProvider.overrideWith((ref) async => _myProfile),
          serviceCategoriesProvider.overrideWith((ref) async => _categories),
          serviceProfileRepositoryProvider.overrideWithValue(_Services()),
          myProviderFeaturesProvider.overrideWith((ref) async => (hasMenu: false, hasDateBooking: false)),
          myOrdersProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ServiceProviderDetailScreen(id: 7)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets("the owner sees all of theirs, the pending one marked, with a pencil to My Services", (tester) async {
      await openDetail(tester, _Provider.new);
      const line = 'Yoga instructor · Hair stylist · Pottery classes (awaiting approval)';
      expect(find.text(line), findsOneWidget);

      final row = find.ancestor(of: find.text(line), matching: find.byType(Row)).first;
      await tester.tap(find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)));
      await tester.pumpAndSettle();
      expect(find.text('My Services'), findsOneWidget);
    });

    testWidgets('a visitor sees every approved service and nothing pending', (tester) async {
      await openDetail(tester, _Visitor.new);
      expect(find.text('Yoga instructor · Hair stylist'), findsOneWidget);
      expect(find.textContaining('Pottery'), findsNothing);
    });

    test('a list card shows the first service and how many more', () {
      ServiceProviderItem item(List<String> names) => ServiceProviderItem.fromJson({
            'id': 1,
            'name': 'Asha',
            'serviceTypes': [
              for (final n in names) {'subcategory': {'name': n}},
            ],
          });
      expect(item(['Yoga instructor', 'Hair stylist', 'Baker']).serviceLabel, 'Yoga instructor +2');
      expect(item(['Yoga instructor']).serviceLabel, 'Yoga instructor');
      expect(item([]).serviceLabel, 'Service Provider');
    });
  });

  test('BUG-088: no two Beautician services share an icon', () {
    const beauticians = [
      'Make up artist',
      'Nail art specialist',
      'Hair stylist',
      'Tattoo artist',
      'Beauty service provider',
      'Mehendi artist',
    ];
    final icons = beauticians.map(ServiceIcons.lookup).toList();
    expect(icons, everyElement(isNotNull));
    expect(icons.toSet(), hasLength(beauticians.length));
    expect(ServiceIcons.lookup('Hair stylist'), 'assets/icons/temaki_beauty-salon.png',
        reason: 'the scissors-and-comb picture is a hair icon');
    expect(ServiceIcons.lookup('Beauty service provider'), isNot(ServiceIcons.lookup('Hair stylist')));
  });
}
