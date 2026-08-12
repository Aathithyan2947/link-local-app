import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/auth/data/auth_models.dart';
import 'package:link_local/features/profile/data/profile_models.dart';
import 'package:link_local/features/services/data/basic_details_fields.dart';

ProfileDetail _profile({
  String name = 'Asha K',
  String? aboutMe,
  int? yearsOfExperience,
  List<IdName> educations = const [],
  List<IdName> professions = const [],
}) =>
    ProfileDetail(
      id: 1,
      name: name,
      userType: 'service_provider',
      aboutMe: aboutMe,
      yearsOfExperience: yearsOfExperience,
      completionPercent: 40,
      educations: educations,
      professions: professions,
      hobbies: const [],
      family: const [],
      pets: const [],
      contacts: const [],
      products: const [],
      serviceTypes: const [],
      hasDelivery: false,
      hasPaymentMethods: false,
    );

void main() {
  const user = AppUser(
    id: 7,
    userType: 'service_provider',
    name: 'Asha K',
    mobile: '9876543210',
    email: 'asha@example.com',
  );

  group('prefillForBasicDetailsField', () {
    test('fills the seeded tutor Basic Details fields from the account', () {
      final profile = _profile(
        aboutMe: 'I teach maths.',
        yearsOfExperience: 6,
        educations: const [IdName(1, 'B.Sc · St. Xavier')],
        professions: const [IdName(2, 'Teacher')],
      );
      String? at(String field) => prefillForBasicDetailsField(field, user: user, profile: profile);

      expect(at('Your Name'), 'Asha K');
      expect(at('Service Phone No.'), '9876543210');
      expect(at('Service Email'), 'asha@example.com');
      expect(at('Years of experience'), '6');
      expect(at('About yourself'), 'I teach maths.');
      expect(at('Profession'), 'Teacher');
      expect(at('Education'), 'B.Sc · St. Xavier');
    });

    test('returns null for fields we hold no data for', () {
      expect(prefillForBasicDetailsField('Favourite subject', user: user, profile: _profile()), isNull);
    });

    test('returns null rather than a blank when the account value is missing', () {
      const mobileOnly = AppUser(id: 7, userType: 'service_provider', name: 'Asha K', mobile: '9876543210');
      expect(prefillForBasicDetailsField('Service Email', user: mobileOnly, profile: _profile()), isNull);
      expect(prefillForBasicDetailsField('About yourself', user: mobileOnly, profile: _profile(aboutMe: '  ')), isNull);
      expect(prefillForBasicDetailsField('Education', user: mobileOnly, profile: _profile()), isNull);
    });

    test('falls back to the profile name when the account has none', () {
      const nameless = AppUser(id: 7, userType: 'service_provider', mobile: '9876543210');
      expect(prefillForBasicDetailsField('Your Name', user: nameless, profile: _profile(name: 'Asha K')), 'Asha K');
    });

    test('tolerates a missing user and profile', () {
      expect(prefillForBasicDetailsField('Service Phone No.'), isNull);
      expect(prefillForBasicDetailsField('Your Name'), isNull);
    });

    test('phone and email win over the looser name pattern', () {
      expect(prefillForBasicDetailsField('Name on email account', user: user, profile: _profile()),
          'asha@example.com');
    });
  });
}
