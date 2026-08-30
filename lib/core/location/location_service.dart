import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'location_models.dart';

/// Produces the most accurate position the device can manage within a time budget.
///
/// The app used to take whatever single-shot [Geolocator.getCurrentPosition]
/// handed back first, which on a cold start is usually the cached network fix —
/// 500 m to 2 km out. This samples the position stream instead, keeps the best
/// fix it sees, and stops as soon as the fix is good enough or has clearly
/// stopped improving.
class LocationService {
  const LocationService();

  /// Key under `NSLocationTemporaryUsageDescriptionDictionary` in Info.plist.
  /// iOS refuses the upgrade request outright if this string is not declared there.
  static const String iosPurposeKey = 'addressCapture';

  /// Long enough for a cold GPS lock outdoors, short enough that a member on a
  /// bad fix is not left staring at a spinner.
  static const Duration defaultBudget = Duration(seconds: 12);

  /// Stop early at this accuracy — comfortably building-level.
  static const double defaultTargetAccuracyM = 15;

  /// A fix older than this is a replay of somewhere the member has been, not a
  /// measurement of where they are standing.
  static const Duration _maxFixAge = Duration(seconds: 30);

  /// Beyond this, a last-known position is likelier to mislead the camera than
  /// to help it.
  static const Duration _maxLastKnownAge = Duration(minutes: 5);

  /// A fix has to beat the running best by this much to count as progress.
  static const double _improvementEpsilonM = 2;

  /// Consecutive non-improving fixes after which the provider is treated as
  /// converged. Waiting out the rest of the budget would not help.
  static const int _stallLimit = 4;

  /// Above this, an Android grant is treated as coarse-only — see [looksCoarseOnly].
  static const double _coarseGrantThresholdM = 500;

  /// Checks services and permission, and on iOS tries to upgrade a reduced-accuracy
  /// grant to full precision for this one use.
  Future<LocationPermissionOutcome> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionOutcome.servicesDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionOutcome.deniedForever;
    }
    if (permission == LocationPermission.denied) {
      return LocationPermissionOutcome.denied;
    }

    // iOS 14+ can hold the permission while withholding precision. Ask for a
    // one-off upgrade; the member sees a system sheet explaining why we want it.
    // Android always reports `precise` here, so the coarse case is caught later
    // by [looksCoarseOnly] instead.
    if (await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced) {
      try {
        final upgraded = await Geolocator.requestTemporaryFullAccuracy(purposeKey: iosPurposeKey);
        if (upgraded != LocationAccuracyStatus.precise) {
          return LocationPermissionOutcome.grantedReduced;
        }
      } catch (_) {
        // Info.plist key missing, or the platform cannot service the request.
        // Not fatal — a coarse permission is still a usable one.
        return LocationPermissionOutcome.grantedReduced;
      }
    }

    return LocationPermissionOutcome.granted;
  }

  /// Emits progressively better fixes and closes once the target accuracy is
  /// met, the budget expires, or the provider converges.
  ///
  /// Only improvements are emitted, so the last event is always the best one.
  /// The first is often a [LocationSource.cached] last-known position, so the
  /// map can paint immediately; it is never confirmable on its own.
  ///
  /// Callers must not assume this terminates only on success — a device that
  /// never produces a usable fix closes the stream having emitted nothing.
  Stream<LocationFix> acquire({
    Duration budget = defaultBudget,
    double targetAccuracyM = defaultTargetAccuracyM,
    bool includeLastKnown = true,
  }) async* {
    if (includeLastKnown) {
      final warm = await _lastKnown();
      if (warm != null) yield warm;
    }

    final deadline = DateTime.now().add(budget);
    LocationFix? best;
    var stalled = 0;

    try {
      await for (final position in Geolocator.getPositionStream(
        locationSettings: _settingsFor(budget),
      )) {
        // Checked first so a device spewing unusable samples still runs out of
        // budget rather than looping forever.
        if (!DateTime.now().isBefore(deadline)) break;
        if (!_isPlausible(position)) continue;

        final fix = LocationFix.fromPosition(position, source: LocationSource.gps);
        final previous = best;

        if (previous != null && !fix.improvesOn(previous, byAtLeastM: _improvementEpsilonM)) {
          if (++stalled >= _stallLimit) break;
          continue;
        }

        best = fix;
        stalled = 0;
        yield fix;

        if ((fix.accuracyM ?? double.infinity) <= targetAccuracyM) break;
      }
    } on TimeoutException {
      // The stream's own timeLimit fired because updates stopped arriving.
      // Whatever was emitted is what the device could manage.
    }
  }

  /// Drains [acquire] and returns its best result, preferring a live fix over a
  /// replayed last-known one however accurate the latter claims to be.
  Future<LocationFix?> acquireBest({
    Duration budget = defaultBudget,
    double targetAccuracyM = defaultTargetAccuracyM,
  }) async {
    LocationFix? live;
    LocationFix? warm;

    await for (final fix in acquire(budget: budget, targetAccuracyM: targetAccuracyM)) {
      if (fix.source == LocationSource.cached) {
        warm ??= fix;
      } else {
        // acquire only emits improvements, so the last one wins.
        live = fix;
      }
    }

    return live ?? warm;
  }

  /// Android gives no direct signal that the member chose "Approximate" in the
  /// permission dialog — [Geolocator.getLocationAccuracy] reports `precise`
  /// either way. The only tell is that fixes never get better than roughly a
  /// kilometre, so this is judged after the fact.
  bool looksCoarseOnly(LocationFix? best) =>
      Platform.isAndroid && (best?.accuracyM ?? 0) > _coarseGrantThresholdM;

  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// A recent last-known position, so the map opens on something real rather
  /// than the hardcoded city fallback while GPS warms up.
  Future<LocationFix?> _lastKnown() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null || position.accuracy <= 0) return null;
      if (DateTime.now().difference(position.timestamp) > _maxLastKnownAge) return null;
      return LocationFix.fromPosition(position, source: LocationSource.cached);
    } catch (_) {
      // Unsupported on some platforms, and never worth failing the flow over.
      return null;
    }
  }

  /// Rejects samples describing something other than where the member is now.
  bool _isPlausible(Position p) {
    if (p.accuracy <= 0) return false; // no confidence figure to reason about
    return DateTime.now().difference(p.timestamp) <= _maxFixAge;
  }

  LocationSettings _settingsFor(Duration budget) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        // Fused location blends GPS with Wi-Fi, cell and sensors, which is what
        // makes an indoor fix usable at all — and members register indoors.
        // Never force the raw LocationManager.
        forceLocationManager: false,
        // Give the convergence loop something to chew on. The fused provider
        // batches internally, so this does not wake the GPS chip every second.
        intervalDuration: const Duration(seconds: 1),
        timeLimit: budget,
      );
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: false,
        // The plugin defaults this to true. The app holds no background
        // location entitlement, so leaving it would be rejected at runtime.
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: false,
        timeLimit: budget,
      );
    }

    return LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      timeLimit: budget,
    );
  }
}
