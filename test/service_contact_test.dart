import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/discovery/data/sp_detail_models.dart';
import 'package:link_local/features/services/data/basic_details_fields.dart';

void main() {
  group('serviceContactUpdates', () {
    test('maps the onboarding answers onto the profile columns', () {
      expect(
        serviceContactUpdates({
          'Your Name': 'Vishnu',
          'Service Phone No.': ' 9998887776 ',
          'Service Email': 'shop@example.com',
          'About yourself': 'I bake.',
        }),
        {'servicePhone': '9998887776', 'serviceEmail': 'shop@example.com'},
      );
    });

    test('never writes the sign-in credential keys', () {
      final updates = serviceContactUpdates({'Service Phone No.': '9998887776'});
      expect(updates.containsKey('mobile'), isFalse);
      expect(updates.containsKey('email'), isFalse);
    });

    test('ignores blank answers so a cleared field does not overwrite', () {
      expect(serviceContactUpdates({'Service Phone No.': '  ', 'Service Email': ''}), isEmpty);
    });

    test('keeps the first match when a subcategory defines two phone fields', () {
      expect(
        serviceContactUpdates({'Service Phone No.': '1111111111', 'Alternate mobile': '2222222222'}),
        {'servicePhone': '1111111111'},
      );
    });
  });

  group('ServiceProviderDetail contact parsing', () {
    test('keeps the published number separate from the sign-in one', () {
      final sp = ServiceProviderDetail.fromJson({
        'id': 1,
        'name': 'Vishnu',
        'user': {'mobile': '8248190710', 'email': 'private@example.com'},
        'servicePhone': '9998887776',
        'serviceEmail': 'shop@example.com',
        'publishedPhone': '9998887776',
      });
      expect(sp.mobile, '8248190710'); // owner-only sign-in number
      expect(sp.servicePhone, '9998887776');
      expect(sp.publishedPhone, '9998887776');
      expect(sp.serviceEmail, 'shop@example.com');
    });

    test('a resident view carries no sign-in details at all', () {
      // The server nulls them for anyone but the owner; only publishedPhone comes through.
      final sp = ServiceProviderDetail.fromJson({
        'id': 1,
        'name': 'Vishnu',
        'user': {'mobile': null, 'email': null},
        'servicePhone': null,
        'publishedPhone': '9998887776',
      });
      expect(sp.mobile, isNull);
      expect(sp.servicePhone, isNull);
      expect(sp.publishedPhone, '9998887776');
    });

    test('an SP who set no business number publishes nothing extra', () {
      // <String, dynamic> because a bare {} infers Map<dynamic, dynamic>; jsonDecode always
      // produces the former, so this matches real payloads.
      final sp = ServiceProviderDetail.fromJson({'id': 1, 'name': 'Vishnu', 'user': <String, dynamic>{}});
      expect(sp.servicePhone, isNull);
      expect(sp.publishedPhone, isNull);
    });
  });
}
