import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/location/location_models.dart';
import '../../../core/location/location_providers.dart';
import '../../../core/location/location_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/address_models.dart';
import '../data/address_repository.dart';

/// What the map hands back: the reverse-geocoded address, plus the fix that
/// produced the pin — so the caller can record *how* the coordinates were
/// captured rather than only what they were.
class MapPinResult {
  const MapPinResult({required this.address, required this.fix});

  final GeoAddress address;
  final LocationFix fix;
}

/// Lets the member pin their building on a map, converging on the most accurate
/// device fix available and showing them how much to trust it.
class AddressMapScreen extends ConsumerStatefulWidget {
  const AddressMapScreen({super.key, this.initial});

  /// When provided, the map opens on this pin (e.g. returning to fix a small
  /// mistake) instead of relocating from scratch.
  final LatLng? initial;

  @override
  ConsumerState<AddressMapScreen> createState() => _AddressMapScreenState();
}

class _AddressMapScreenState extends ConsumerState<AddressMapScreen> {
  static const _fallback = LatLng(19.2503, 72.9780); // Thane / Ghodbunder Rd

  /// Close enough to pick out one building from its neighbours. The screen used
  /// to open at 15, where every rooftop looks the same.
  static const _buildingZoom = 18.0;

  /// Used while the fix is still too coarse to justify claiming a building.
  static const _areaZoom = 16.0;

  /// Mutes shop and transit clutter so the member's own building is the
  /// findable thing on screen.
  static const _mapStyle = '['
      '{"featureType":"poi.business","stylers":[{"visibility":"off"}]},'
      '{"featureType":"poi.attraction","stylers":[{"visibility":"off"}]},'
      '{"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}'
      ']';

  GoogleMapController? _map;
  StreamSubscription<LocationFix>? _locating;

  LatLng _center = _fallback;

  /// Best fix the device has produced so far; null until it produces one.
  LocationFix? _fix;

  /// Set once the member pans the map themselves. After that the camera stops
  /// moving under them, and the pin counts as their own placement.
  bool _movedByUser = false;

  /// Guards [_movedByUser] against our own camera animations, since
  /// `onCameraMoveStarted` fires for programmatic moves too.
  bool _programmaticMove = false;

  bool _searching = false;
  bool _resolving = false;
  String? _notice;
  LocationPermissionOutcome? _permission;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _center = initial;
      // Returning to an existing pin is already the member's own placement.
      _movedByUser = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToCurrentLocation());
    }
  }

  @override
  void dispose() {
    _locating?.cancel();
    _map?.dispose();
    super.dispose();
  }

  /// Requests permission, then converges on the best fix the device can manage,
  /// recentring as each better one arrives.
  Future<void> _goToCurrentLocation() async {
    await _locating?.cancel();
    setState(() {
      _searching = true;
      _notice = null;
      _movedByUser = false;
    });

    final service = ref.read(locationServiceProvider);
    final outcome = await service.ensurePermission();
    if (!mounted) return;

    setState(() {
      _permission = outcome;
      _notice = outcome.message;
    });

    if (!outcome.canLocate) {
      setState(() => _searching = false);
      return;
    }

    _locating = service.acquire().listen(
      (fix) {
        if (!mounted) return;
        setState(() => _fix = fix);
        // Never yank the camera away from someone already placing their pin.
        if (_movedByUser) return;
        _center = LatLng(fix.latitude, fix.longitude);
        _programmaticMove = true;
        _map?.animateCamera(
          CameraUpdate.newLatLngZoom(_center, fix.isConfirmable ? _buildingZoom : _areaZoom),
        );
      },
      onError: (_) => _settle(service),
      onDone: () => _settle(service),
      cancelOnError: true,
    );
  }

  /// Called once the stream closes: the device has given us the best it can, so
  /// the notice switches from "working on it" to "here is what you got".
  void _settle(LocationService service) {
    if (!mounted) return;
    setState(() {
      _searching = false;
      if (_fix == null) {
        _notice = 'Could not get your location. Move the map to your building.';
      } else if (service.looksCoarseOnly(_fix)) {
        _permission = LocationPermissionOutcome.grantedReduced;
        _notice = LocationPermissionOutcome.grantedReduced.message;
      } else if (_fix!.tier == AccuracyTier.poor) {
        _notice = 'Weak signal here. Check the pin sits on your building before confirming.';
      } else {
        _notice = null;
      }
    });
  }

  Future<void> _confirm() async {
    // Converge, then warn. A poor fix the member never adjusted is the one case
    // worth a second look — but never a hard block, since plenty of people
    // register indoors where the device genuinely cannot do better.
    if (!_movedByUser && !(_fix?.isConfirmable ?? false)) {
      if (await _askAboutPoorFix() != true) return;
      if (!mounted) return;
    }

    setState(() => _resolving = true);
    final fix = _movedByUser || _fix == null
        ? LocationFix.manual(latitude: _center.latitude, longitude: _center.longitude)
        : _fix!;

    try {
      final geo = await ref
          .read(addressRepositoryProvider)
          .reverseGeocode(_center.latitude, _center.longitude);
      if (mounted) Navigator.of(context).pop(MapPinResult(address: geo, fix: fix));
    } catch (_) {
      // Losing the address lookup shouldn't lose the pin the member just placed.
      if (mounted) {
        Navigator.of(context).pop(MapPinResult(
          address: GeoAddress(latitude: _center.latitude, longitude: _center.longitude),
          fix: fix,
        ));
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<bool?> _askAboutPoorFix() {
    final label = _fix?.accuracyLabel;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Is the pin on your building?'),
        content: Text(
          label == null
              ? "We couldn't get a location fix, so the pin is wherever the map opened."
              : 'The best fix we got is $label, which could be a few streets out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Let me adjust'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, confirm'),
          ),
        ],
      ),
    );
  }

  /// The reported confidence radius, drawn to scale. This is what turns an
  /// invisible bad fix into an obvious one — a circle swallowing four blocks
  /// tells the member to move the pin far better than any wording can.
  Set<Circle> get _accuracyCircle {
    final fix = _fix;
    final radius = fix?.accuracyM;
    if (fix == null || radius == null || _movedByUser) return const {};
    return {
      Circle(
        circleId: const CircleId('accuracy'),
        center: LatLng(fix.latitude, fix.longitude),
        radius: radius,
        fillColor: AppColors.primary.withValues(alpha: 0.12),
        strokeColor: AppColors.primary.withValues(alpha: 0.45),
        strokeWidth: 1,
      ),
    };
  }

  (String, Color) get _accuracyChip {
    final fix = _fix;
    if (fix == null) {
      return _searching
          ? ('Finding your location…', AppColors.textSecondary)
          : ('No location fix', AppColors.error);
    }
    final label = fix.accuracyLabel;
    if (label == null) return ('Pin placed manually', AppColors.textSecondary);
    return switch (fix.tier) {
      AccuracyTier.excellent || AccuracyTier.good => ('Accurate to $label', AppColors.success),
      AccuracyTier.fair => ('Accurate to $label', AppColors.warning),
      _ => ('$label — move the pin to your building', AppColors.error),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (chipLabel, chipColor) = _accuracyChip;

    return Scaffold(
      appBar: AppBar(title: const Text('Pin your location')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: _areaZoom),
            style: _mapStyle,
            onMapCreated: (controller) => _map = controller,
            myLocationEnabled: true,
            myLocationButtonEnabled: false, // the recentre FAB below does this
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            tiltGesturesEnabled: false,
            rotateGesturesEnabled: false,
            buildingsEnabled: true,
            circles: _accuracyCircle,
            onCameraMoveStarted: () {
              if (_programmaticMove || _movedByUser) return;
              setState(() => _movedByUser = true);
            },
            onCameraMove: (position) => _center = position.target,
            onCameraIdle: () {
              _programmaticMove = false;
              setState(() {}); // refresh the chip and the circle
            },
          ),
          // Fixed centre pin: the map moves under it, so the pin is always
          // exactly where the camera is pointing.
          const Padding(
            padding: EdgeInsets.only(bottom: 36),
            child: Icon(Icons.location_on, color: AppColors.primary, size: 48),
          ),
          Positioned(
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.my_location, size: 14, color: chipColor),
                    ),
                  Text(
                    chipLabel,
                    style: TextStyle(color: chipColor, fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 150,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
              onPressed: _searching ? null : _goToCurrentLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 16)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _notice ?? 'Move the map to position the pin on your building',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _notice != null ? AppColors.warning : AppColors.textSecondary,
                    ),
                  ),
                  // Permission problems are fixable, but only in Settings — so
                  // offer the trip rather than leaving the member stuck.
                  if (_permission?.isFixableInSettings ?? false) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => ref.read(locationServiceProvider).openAppSettings(),
                      child: const Text('Open Settings'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Confirm location',
                    loading: _resolving,
                    onPressed: _confirm,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
