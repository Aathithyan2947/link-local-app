import 'package:geolocator/geolocator.dart';

/// How a coordinate was obtained. Persisted alongside the address so a pin that
/// later turns out to be wrong can be traced back to the way it was captured.
enum LocationSource {
  /// A live fix from the device's location provider.
  gps('gps'),

  /// The platform's last-known position, replayed so the map can open on
  /// something real while GPS warms up. Never accurate enough to confirm an
  /// address on — [LocationFix.isConfirmable] rejects it.
  cached('cached'),

  /// The member positioned the pin themselves. Authoritative whatever the
  /// device reported.
  manualPin('manual_pin'),

  /// Carried over from a curated Address Master locality.
  master('master');

  const LocationSource(this.wireValue);

  /// The value stored in `addresses.location_source`.
  final String wireValue;
}

/// Accuracy bands, named for what they mean on the ground rather than in metres.
/// Both the accuracy chip and the confirm gate branch on these.
enum AccuracyTier {
  /// Up to 10 m — the right building.
  excellent,

  /// Up to 30 m — the right building or the one next door.
  good,

  /// Up to 100 m — the right lane, roughly.
  fair,

  /// Beyond 100 m — suburb-level. A cached network fix looks like this, and it
  /// is what the app silently accepted before this existed.
  poor,
}

/// A single position sample, carrying everything the UI and the backend need in
/// order to decide how much to trust it.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.timestamp,
    required this.source,
    this.isMocked = false,
  });

  /// Wraps a raw geolocator [Position].
  factory LocationFix.fromPosition(Position p, {required LocationSource source}) => LocationFix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyM: p.accuracy,
        timestamp: p.timestamp,
        source: source,
        isMocked: p.isMocked,
      );

  /// A pin the member placed by hand. [accuracyM] is deliberately null: a hand
  /// placement is not a measurement, and recording it as `0` would be
  /// indistinguishable from a flawless fix.
  factory LocationFix.manual({required double latitude, required double longitude}) => LocationFix(
        latitude: latitude,
        longitude: longitude,
        accuracyM: null,
        timestamp: DateTime.now(),
        source: LocationSource.manualPin,
      );

  /// Coordinates carried over from a curated Address Master locality. Trusted
  /// like a hand-placed pin: a human already vetted it, and there is no device
  /// measurement behind it to band.
  factory LocationFix.fromMaster({required double latitude, required double longitude}) =>
      LocationFix(
        latitude: latitude,
        longitude: longitude,
        accuracyM: null,
        timestamp: DateTime.now(),
        source: LocationSource.master,
      );

  final double latitude;
  final double longitude;

  /// Radius in metres of the confidence circle the platform reports, or null
  /// when this fix is not a measurement (see [LocationFix.manual]).
  final double? accuracyM;

  final DateTime timestamp;
  final LocationSource source;

  /// The device reported this as a simulated position — developer options on
  /// Android, or a mock provider. Surfaced rather than silently trusted.
  final bool isMocked;

  /// Null when there is no measurement to band.
  AccuracyTier? get tier {
    final a = accuracyM;
    if (a == null) return null;
    if (a <= 10) return AccuracyTier.excellent;
    if (a <= 30) return AccuracyTier.good;
    if (a <= 100) return AccuracyTier.fair;
    return AccuracyTier.poor;
  }

  /// Whether this fix is precise enough to accept without asking the member to
  /// check the pin. A hand-placed pin always is; a cached one never is, since
  /// confirming an address on a stale network fix defeats the whole exercise.
  bool get isConfirmable => switch (source) {
        LocationSource.manualPin || LocationSource.master => true,
        LocationSource.cached => false,
        _ => tier != null && tier != AccuracyTier.poor,
      };

  /// The figure shown on the accuracy chip — "±8 m", "±1.2 km".
  String? get accuracyLabel {
    final a = accuracyM;
    if (a == null) return null;
    return a >= 1000 ? '±${(a / 1000).toStringAsFixed(1)} km' : '±${a.round()} m';
  }

  /// The value persisted as `location_source`. A mocked fix is recorded as such
  /// rather than being filed away as a genuine measurement.
  String get sourceWireValue => isMocked ? 'mocked' : source.wireValue;

  /// Whether this fix is a meaningful improvement on [previous]. Used to detect
  /// convergence — a provider that has stopped improving will not improve.
  bool improvesOn(LocationFix previous, {double byAtLeastM = 2}) {
    final mine = accuracyM;
    final theirs = previous.accuracyM;
    if (mine == null) return false;
    if (theirs == null) return true;
    return theirs - mine >= byAtLeastM;
  }
}

/// The result of asking for location permission, flattened into the cases the
/// UI actually branches on.
enum LocationPermissionOutcome {
  /// Full precision available.
  granted,

  /// Permission held, but the platform is deliberately degrading precision:
  /// Android 12+ "Approximate", or iOS with "Precise Location" switched off.
  /// Fixes land around a kilometre out, so this is worth surfacing rather than
  /// silently accepting.
  grantedReduced,

  denied,
  deniedForever,
  servicesDisabled,
}

extension LocationPermissionOutcomeX on LocationPermissionOutcome {
  /// Whether it is worth asking the device for a position at all.
  bool get canLocate =>
      this == LocationPermissionOutcome.granted || this == LocationPermissionOutcome.grantedReduced;

  /// Whether the fix is worth offering a "fix this in Settings" action for.
  bool get isFixableInSettings =>
      this == LocationPermissionOutcome.deniedForever ||
      this == LocationPermissionOutcome.grantedReduced;

  /// Member-facing explanation. Null when nothing is wrong.
  String? get message => switch (this) {
        LocationPermissionOutcome.granted => null,
        LocationPermissionOutcome.grantedReduced =>
          'Precise location is off, so your pin could be a kilometre out. '
              'Turn it on in Settings, or move the pin to your building.',
        LocationPermissionOutcome.denied =>
          'Location permission denied. You can still drop the pin manually.',
        LocationPermissionOutcome.deniedForever =>
          'Location permission is blocked. Enable it in Settings, or drop the pin manually.',
        LocationPermissionOutcome.servicesDisabled =>
          'Location services are off. Turn them on, or drop the pin manually.',
      };
}
