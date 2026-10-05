/// Parses a timestamp from the API — an instant, sent in UTC (`2026-10-04T10:00:00.000Z`) —
/// into the phone's local time, so a formatted clock time is what the user expects
/// (3:30 PM in India, not the raw 10:00 AM UTC).
///
/// Only for real moments in time (created / placed / paid / sent at). Calendar values — an
/// event's date or start time, a booking slot, a date of birth — mean "this day / this clock
/// time" wherever you are and must stay as sent; converting them would shift them.
DateTime? parseServerTime(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse('$value')?.toLocal();
}
