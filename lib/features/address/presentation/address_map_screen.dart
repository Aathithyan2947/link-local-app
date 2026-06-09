import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/address_models.dart';
import '../data/address_repository.dart';

/// Lets the user pin a location on a map; requests device location to start at
/// the user's accurate position. Returns a reverse-geocoded [GeoAddress].
class AddressMapScreen extends ConsumerStatefulWidget {
  const AddressMapScreen({super.key});

  @override
  ConsumerState<AddressMapScreen> createState() => _AddressMapScreenState();
}

class _AddressMapScreenState extends ConsumerState<AddressMapScreen> {
  final _controller = MapController();
  static const _fallback = LatLng(19.2503, 72.9780); // Thane / Ghodbunder Rd
  LatLng _center = _fallback;
  bool _resolving = false;
  bool _locating = true;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _goToCurrentLocation());
  }

  /// Requests permission and recenters the map on the device's location.
  Future<void> _goToCurrentLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _notice = 'Location services are off. Enable them or drop the pin manually.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _notice = 'Location permission denied. You can still drop the pin manually.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final here = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = here;
        _notice = null;
      });
      _controller.move(here, 16);
    } catch (e) {
      setState(() => _notice = 'Could not get your location. Drop the pin manually.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _confirm() async {
    setState(() => _resolving = true);
    try {
      final geo = await ref
          .read(addressRepositoryProvider)
          .reverseGeocode(_center.latitude, _center.longitude);
      if (mounted) Navigator.of(context).pop(geo);
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pop(GeoAddress(latitude: _center.latitude, longitude: _center.longitude));
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pin your location')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onPositionChanged: (camera, _) => _center = camera.center,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.sentellent.link_local',
              ),
            ],
          ),
          // Fixed center pin.
          const Padding(
            padding: EdgeInsets.only(bottom: 36),
            child: Icon(Icons.location_on, color: AppColors.primary, size: 48),
          ),
          if (_locating)
            Positioned(
              top: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Finding your location...'),
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
              onPressed: _locating ? null : _goToCurrentLocation,
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
                    style: TextStyle(color: _notice != null ? AppColors.warning : AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(label: 'Confirm location', loading: _resolving, onPressed: _confirm),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
