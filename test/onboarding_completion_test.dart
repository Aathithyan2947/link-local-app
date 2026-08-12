import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/services/data/service_profile_repository.dart';
import 'package:link_local/features/services/presentation/category_fields_form_screen.dart';

CustomField field(
  int id, {
  String category = 'basic_details',
  bool required = false,
  String? value,
}) =>
    CustomField(
      fieldId: id,
      subcategoryName: 'Tutor',
      category: category,
      fieldName: 'Field $id',
      fieldType: 'text',
      isRequired: required,
      value: value,
    );

void main() {
  group('hasUnansweredRequiredField', () {
    test('an all-optional set never blocks, however empty', () {
      // The Tutor set: 15 fields, none required. Whether they FINISHED is recorded on the
      // profile now, so this helper must not pretend to answer that question.
      final fields = [for (var i = 1; i <= 15; i++) field(i)];
      expect(hasUnansweredRequiredField(fields), isFalse);
    });

    test('an unanswered required field is reported', () {
      expect(hasUnansweredRequiredField([field(1, required: true), field(2, value: 'x')]), isTrue);
    });

    test('a blank or whitespace-only answer does not satisfy a required field', () {
      expect(hasUnansweredRequiredField([field(1, required: true, value: '')]), isTrue);
      expect(hasUnansweredRequiredField([field(1, required: true, value: '   ')]), isTrue);
    });

    test('every required field answered is clear', () {
      expect(hasUnansweredRequiredField([field(1, required: true, value: 'Asha K'), field(2)]), isFalse);
    });

    test('no configured fields is clear', () {
      expect(hasUnansweredRequiredField(const []), isFalse);
    });
  });

  group('onboardingRelevantFields', () {
    final fields = [
      field(1),
      field(2, category: 'travel'),
      field(3, category: 'payment'),
      field(4, category: 'delivery'),
    ];

    test('drops the excluded categories', () {
      final relevant = onboardingRelevantFields(fields, hasMenu: false, excluding: const {'payment'});
      expect(relevant.map((f) => f.category), ['basic_details', 'travel', 'delivery']);
    });

    test('keeps everything when nothing is excluded', () {
      expect(onboardingRelevantFields(fields, hasMenu: false).length, 4);
    });

    test('a payment-only SP is judged on nothing once payment is excluded', () {
      final relevant =
          onboardingRelevantFields([field(3, category: 'payment')], hasMenu: false, excluding: const {'payment'});
      expect(relevant, isEmpty);
      expect(hasUnansweredRequiredField(relevant), isFalse);
    });
  });
}
