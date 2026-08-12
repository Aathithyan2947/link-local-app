import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/business/presentation/setup/sp_setup_wizard_screen.dart';
import 'package:link_local/features/profile/data/profile_models.dart';

void main() {
  group('professionsPayload', () {
    test('replaces the first entry and keeps the rest by master id', () {
      const existing = [
        IdName(1, 'Teacher', masterId: 10),
        IdName(2, 'Tutor', subtitle: 'Acme Coaching', masterId: 11),
      ];
      expect(professionsPayload('Maths Teacher', existing), [
        {'category': 'Maths Teacher'},
        {'professionMasterId': 11, 'companyOrDetail': 'Acme Coaching'},
      ]);
    });

    test('is the only entry when the profile had none', () {
      expect(professionsPayload('Maths Teacher', const []), [
        {'category': 'Maths Teacher'},
      ]);
    });

    test('writes nothing when the title is unchanged', () {
      const existing = [IdName(1, 'Teacher', masterId: 10)];
      expect(professionsPayload('Teacher', existing), isNull);
    });

    test('writes nothing for an empty title', () {
      expect(professionsPayload('', const [IdName(1, 'Teacher', masterId: 10)]), isNull);
      expect(professionsPayload('', const []), isNull);
    });

    test('drops trailing entries with no master id rather than minting a junk category', () {
      const existing = [
        IdName(1, 'Teacher', masterId: 10),
        IdName(2, 'Profession'), // legacy row with no catalog link
      ];
      expect(professionsPayload('Maths Teacher', existing), [
        {'category': 'Maths Teacher'},
      ]);
    });

    test('omits companyOrDetail when the kept entry has none', () {
      const existing = [IdName(1, 'Teacher', masterId: 10), IdName(2, 'Tutor', masterId: 11)];
      expect(professionsPayload('Maths Teacher', existing), [
        {'category': 'Maths Teacher'},
        {'professionMasterId': 11},
      ]);
    });
  });

  group('ProfileDetail.fromJson', () {
    test('reads yearsOfExperience and the profession master id', () {
      final p = ProfileDetail.fromJson({
        'id': 1,
        'name': 'Asha K',
        'yearsOfExperience': 6,
        'professions': [
          {
            'id': 2,
            'companyOrDetail': 'Acme Coaching',
            'professionMaster': {'id': 11, 'category': 'Tutor'},
          },
        ],
      });
      expect(p.yearsOfExperience, 6);
      expect(p.professions.single.id, 2);
      expect(p.professions.single.masterId, 11);
      expect(p.professions.single.label, 'Tutor');
      expect(p.professions.single.subtitle, 'Acme Coaching');
    });

    test('leaves masterId null for a profession with no catalog link', () {
      final p = ProfileDetail.fromJson({
        'id': 1,
        'name': 'Asha K',
        'professions': [
          {'id': 3},
        ],
      });
      expect(p.yearsOfExperience, isNull);
      expect(p.professions.single.masterId, isNull);
      expect(p.professions.single.label, 'Profession');
    });
  });
}
