import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:link_local/core/time/server_time.dart';
import 'package:link_local/features/home/data/home_models.dart';
import 'package:link_local/features/messages/data/message_models.dart';
import 'package:link_local/features/notifications/data/notification_models.dart';
import 'package:link_local/features/orders/data/order_models.dart';

/// 10:00 UTC — 3:30 PM in India.
const _utc = '2026-10-04T10:00:00.000Z';
final _expectedLocal = DateTime.utc(2026, 10, 4, 10).toLocal();
final _inIndia = DateTime.now().timeZoneOffset == const Duration(hours: 5, minutes: 30);

void _isLocal(DateTime? t) {
  expect(t, isNotNull);
  expect(t!.isUtc, isFalse, reason: 'formatting a UTC DateTime prints UTC clock time');
  expect(t, _expectedLocal);
}

void main() {
  group('parseServerTime', () {
    test('converts a UTC timestamp to local time', () => _isLocal(parseServerTime(_utc)));
    test('in India, 10:00 UTC reads as 3:30 PM', () {
      final shown = DateFormat('MMM d, h:mm a').format(parseServerTime(_utc)!);
      expect(shown, DateFormat('MMM d, h:mm a').format(_expectedLocal));
      if (_inIndia) expect(shown, 'Oct 4, 3:30 PM');
    });
    test('null or garbage → null', () {
      expect(parseServerTime(null), isNull);
      expect(parseServerTime('not a date'), isNull);
    });
  });

  group('timestamps in models are local', () {
    test("an order's placed time (the bug)", () {
      final o = OrderModel.fromJson({'id': 1, 'status': 'accepted', 'placedAt': _utc, 'items': [], 'payments': []});
      _isLocal(o.placedAt);
    });
    test(
      'a payment time',
      () => _isLocal(OrderPaymentModel.fromJson({'id': 1, 'paidAt': _utc, 'createdAt': _utc}).paidAt),
    );
    test('a notification time', () {
      _isLocal(AppNotification.fromJson({'id': 1, 'title': 'x', 'createdAt': _utc}).createdAt);
    });
    test('a chat message and the conversation list', () {
      _isLocal(ChatMessage.fromJson({'id': 1, 'senderId': 2, 'content': 'hi', 'createdAt': _utc}).createdAt);
      _isLocal(
        Conversation.fromJson({
          'other': {'id': 2},
          'lastAt': _utc,
        }).lastAt,
      );
    });
    test('a discussion post', () => _isLocal(DiscussionItem.fromJson({'id': 1, 'createdAt': _utc}).createdAt));
  });

  test("an event's date stays the calendar day it was set for (not shifted)", () {
    final e = WorkshopItem.fromJson({'id': 1, 'title': 'x', 'date': '2026-09-15T00:00:00.000Z'});
    expect(e.date!.isUtc, isTrue, reason: 'calendar values are kept as sent');
    expect(e.date!.day, 15);
  });

  test('every server timestamp goes through parseServerTime', () {
    // Raw parsing is allowed only for calendar values (event date / start time, date of birth).
    const allowed = ["j['date']", "j['startTime']", 'dateOfBirth', 'server_time.dart'];
    final offenders = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (!l.contains('DateTime.tryParse')) continue;
        if (allowed.any((a) => l.contains(a) || f.path.endsWith(a))) continue;
        offenders.add('${f.path}:${i + 1}: ${l.trim()}');
      }
    }
    expect(offenders, isEmpty, reason: 'parse API timestamps with parseServerTime so they show in local time');
  });
}
