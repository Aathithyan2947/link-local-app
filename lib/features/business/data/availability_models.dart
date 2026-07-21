// Models for SP weekly availability, blackout dates, and the bookable slots
// residents choose from at checkout.

const _weekdayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// 0=Sun … 6=Sat → "Mon".
String weekdayShort(int d) => _weekdayShort[d % 7];

/// "16:00" → "4:00 PM".
String formatHm(String hhmm) {
  final parts = hhmm.split(':');
  var h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? parts[1] : '00';
  final ampm = h >= 12 ? 'PM' : 'AM';
  h = h % 12;
  if (h == 0) h = 12;
  return '$h:$m $ampm';
}

/// The SP's weekly availability template.
class SpAvailability {
  const SpAvailability({
    required this.workingDays,
    required this.startTime,
    required this.endTime,
    this.slotMinutes,
    this.willingToTravel = false,
    this.maxTravelKm,
    this.horizonDays = 14,
  });

  final List<int> workingDays; // 0=Sun … 6=Sat
  final String startTime; // "HH:MM"
  final String endTime; // "HH:MM"
  final int? slotMinutes; // null ⇒ one slot spanning the whole daily window
  final bool willingToTravel;
  final double? maxTravelKm;
  final int horizonDays;

  /// "Mon–Fri" for a contiguous run, else "Mon, Wed, Fri".
  String get daysLabel {
    final sorted = [...workingDays]..sort();
    if (sorted.isEmpty) return '—';
    final contiguous = sorted.length > 1 && sorted.last - sorted.first == sorted.length - 1;
    if (contiguous) return '${weekdayShort(sorted.first)}–${weekdayShort(sorted.last)}';
    return sorted.map(weekdayShort).join(', ');
  }

  String get timeLabel => '${formatHm(startTime)} – ${formatHm(endTime)}';

  factory SpAvailability.fromJson(Map<String, dynamic> j) => SpAvailability(
        workingDays: ((j['workingDays'] as List?) ?? []).map((e) => e is int ? e : int.parse('$e')).toList(),
        startTime: (j['startTime'] as String?) ?? '09:00',
        endTime: (j['endTime'] as String?) ?? '17:00',
        slotMinutes: j['slotMinutes'] == null ? null : (j['slotMinutes'] as num).toInt(),
        willingToTravel: (j['willingToTravel'] as bool?) ?? false,
        maxTravelKm: j['maxTravelKm'] == null ? null : double.tryParse('${j['maxTravelKm']}'),
        horizonDays: (j['horizonDays'] as num?)?.toInt() ?? 14,
      );

  Map<String, dynamic> toJson() => {
        'workingDays': workingDays,
        'startTime': startTime,
        'endTime': endTime,
        'slotMinutes': slotMinutes,
        'willingToTravel': willingToTravel,
        if (maxTravelKm != null) 'maxTravelKm': maxTravelKm,
        'horizonDays': horizonDays,
      };
}

/// A specific day the SP marked off (overrides the weekly template).
class Blackout {
  const Blackout({required this.id, required this.date, this.reason});
  final int id;
  final String date; // "YYYY-MM-DD"
  final String? reason;

  String get label {
    final d = DateTime.parse(date);
    return '${weekdayShort(d.weekday % 7)}, ${_monthShort[d.month - 1]} ${d.day} ${d.year}';
  }

  factory Blackout.fromJson(Map<String, dynamic> j) => Blackout(
        id: (j['id'] as num).toInt(),
        date: (j['unavailableDate'] as String).substring(0, 10),
        reason: j['reason'] as String?,
      );
}

/// The GET /me/availability payload — template + blackout list.
class AvailabilityData {
  const AvailabilityData({this.availability, this.blackouts = const []});
  final SpAvailability? availability;
  final List<Blackout> blackouts;

  factory AvailabilityData.fromJson(Map<String, dynamic> j) => AvailabilityData(
        availability:
            j['availability'] == null ? null : SpAvailability.fromJson(j['availability'] as Map<String, dynamic>),
        blackouts: ((j['blackouts'] as List?) ?? [])
            .map((e) => Blackout.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A bookable, date-anchored slot a resident can pick at checkout.
class OpenSlot {
  const OpenSlot({required this.date, required this.startTime, required this.endTime});
  final String date; // "YYYY-MM-DD"
  final String startTime; // "HH:MM"
  final String endTime; // "HH:MM"

  DateTime get dateObj => DateTime.parse(date);

  String get dayLabel {
    final d = dateObj;
    final today = DateTime.now();
    final diff = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return '${weekdayShort(d.weekday % 7)}, ${_monthShort[d.month - 1]} ${d.day}';
  }

  String get timeLabel => '${formatHm(startTime)} – ${formatHm(endTime)}';

  factory OpenSlot.fromJson(Map<String, dynamic> j) => OpenSlot(
        date: j['date'] as String,
        startTime: j['startTime'] as String,
        endTime: j['endTime'] as String,
      );

  Map<String, dynamic> toJson() => {'date': date, 'startTime': startTime, 'endTime': endTime};
}
