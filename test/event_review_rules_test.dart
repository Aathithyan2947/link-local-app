import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/discovery/data/event_detail_models.dart';

EventDetail _event(Map<String, dynamic> extra) =>
    EventDetail.fromJson({'id': 1, 'title': 'T', 'mode': 'offline', 'creator': {'id': 5}, ...extra});

void main() {
  test('review permission comes from the backend flags', () {
    final host = _event({'isHost': true, 'canReview': false, 'hasStarted': true});
    expect(host.isHost, isTrue);
    expect(host.canReview, isFalse);

    final attendee = _event({'canReview': true, 'hasStarted': true, 'myAttendance': {'status': 'joined'}});
    expect(attendee.canReview, isTrue);
  });

  test('older responses without the flags never allow a review', () {
    final old = _event({});
    expect(old.canReview, isFalse);
    expect(old.isHost, isFalse);
  });

  test('picked location carries its map position', () {
    final e = _event({'location': 'X', 'latitude': '19.2300000', 'longitude': 72.97, 'googlePlaceId': 'P1'});
    expect(e.latitude, 19.23);
    expect(e.longitude, 72.97);
    expect(e.googlePlaceId, 'P1');
  });
}
