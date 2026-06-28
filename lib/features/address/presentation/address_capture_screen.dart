import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/auth_header.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../reference/reference_models.dart';
import '../../reference/reference_repository.dart';
import '../data/address_models.dart';
import '../data/address_repository.dart';
import 'address_map_screen.dart';

class AddressCaptureScreen extends ConsumerStatefulWidget {
  const AddressCaptureScreen({super.key});

  @override
  ConsumerState<AddressCaptureScreen> createState() => _AddressCaptureScreenState();
}

class _AddressCaptureScreenState extends ConsumerState<AddressCaptureScreen> {
  final _search = TextEditingController();
  City? _city;
  String? _state;
  LatLng? _picked;

  // Per-city address-form config + a controller per field key.
  List<CityAddressField> _fields = [];
  final Map<String, TextEditingController> _fieldCtrls = {};
  final Map<String, String> _prefill = {};
  bool _fieldsLoading = false;
  bool _locating = false;

  Timer? _debounce;
  List<MasterSuggestion> _suggestions = [];
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Try to auto-select the city from the device location once cities have loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoDetectCity());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<City> get _cities => ref.read(citiesProvider).asData?.value ?? [];

  City? _cityById(int? id) {
    if (id == null) return null;
    for (final c in _cities) {
      if (c.id == id) return c;
    }
    return null;
  }

  City? _cityByName(String? name) {
    final n = name?.trim().toLowerCase();
    if (n == null || n.isEmpty) return null;
    // Exact match first, then a loose contains match so geocoder variants like
    // "Mumbai Suburban" / "Greater Mumbai" still resolve to the serviceable city.
    for (final c in _cities) {
      if (c.name.toLowerCase() == n) return c;
    }
    for (final c in _cities) {
      final cn = c.name.toLowerCase();
      if (n.contains(cn) || cn.contains(n)) return c;
    }
    return null;
  }

  /// Loads the selected city's form config and (re)builds the field controllers,
  /// seeding them from any prefill captured via search / map / current location.
  Future<void> _loadFields() async {
    if (_city == null) return;
    setState(() => _fieldsLoading = true);
    try {
      final fields = await ref.read(addressRepositoryProvider).getCityAddressFields(_city!.id);
      for (final c in _fieldCtrls.values) {
        c.dispose();
      }
      _fieldCtrls.clear();
      for (final f in fields) {
        _fieldCtrls[f.fieldKey] = TextEditingController(text: _prefill[f.fieldKey] ?? '');
      }
      if (mounted) setState(() => _fields = fields);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _fieldsLoading = false);
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final res = await ref.read(addressRepositoryProvider).searchDirectory(q.trim());
        if (mounted) setState(() => _suggestions = res.localities);
      } catch (_) {
        if (mounted) setState(() => _suggestions = []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  /// Applies a curated Address Master locality: sets city/state, prefills the lane/area/
  /// suburb/pincode fields, then opens the confirm sheet.
  Future<void> _applyMaster(MasterSuggestion s, {bool openSheet = true, LatLng? pin}) async {
    if (pin != null) {
      _picked = pin;
    } else if (s.latitude != null && s.longitude != null) {
      _picked = LatLng(s.latitude!, s.longitude!);
    }
    _prefill
      // Selecting a directory suggestion DOES fill the building/complex name.
      ..['building'] = s.complex ?? ''
      ..['lane1'] = s.lane1 ?? ''
      ..['lane2'] = s.lane2 ?? ''
      ..['area'] = s.area ?? ''
      ..['suburb'] = s.suburb ?? ''
      ..['pincode'] = s.pincode ?? '';
    _city = _cityById(s.cityId) ?? _cityByName(s.city) ?? _city;
    _state = _city?.state ?? s.state ?? _state;
    setState(() => _suggestions = []);
    await _loadFields();
    if (openSheet && mounted) _openConfirmSheet();
  }

  Future<void> _applySuggestion(MasterSuggestion s) async {
    _search.text = s.title;
    await _applyMaster(s);
  }

  /// High-accuracy device position (throws a user-facing message on failure).
  Future<Position> _devicePosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw 'Location services are off.';
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw 'Location permission denied.';
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Silent best-effort: pick the user's city from GPS on screen load. Never shows an error.
  Future<void> _autoDetectCity() async {
    try {
      await ref.read(citiesProvider.future); // ensure the city list is loaded
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final repo = ref.read(addressRepositoryProvider);
      // Curated master gives the serviceable city directly (best-effort; endpoint optional).
      City? detected;
      try {
        final near = await repo.nearbyMaster(pos.latitude, pos.longitude);
        if (near.isNotEmpty) detected = _cityById(near.first.cityId) ?? _cityByName(near.first.city);
      } catch (_) {}
      // Fall back to map data (reverse geocoding) for the city name.
      detected ??= _cityByName((await repo.reverseGeocode(pos.latitude, pos.longitude)).city);

      // Only auto-select when it's a city Link Local actually serves.
      if (detected != null && mounted) {
        setState(() {
          _city = detected;
          _state = detected!.state ?? _state;
          _picked = LatLng(pos.latitude, pos.longitude);
        });
        await _loadFields();
      }
    } catch (_) {
      // Ignore — the user can still select their city manually.
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _error = null;
      _locating = true;
    });
    try {
      final pos = await _devicePosition();
      await _resolveLocation(pos.latitude, pos.longitude);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Resolves a GPS pin to a serviceable city using the curated master (preferred) and map
  /// data (fallback). Prefills + locks the city/state ONLY when the location falls in a city
  /// Link Local serves; otherwise it tells the user and leaves the city for manual selection.
  Future<void> _resolveLocation(double lat, double lng) async {
    final repo = ref.read(addressRepositoryProvider);

    // 1) Curated Address Master within 2 km → the serviceable city directly (best-effort).
    MasterSuggestion? hit;
    try {
      final near = await repo.nearbyMaster(lat, lng);
      if (near.isNotEmpty) hit = near.first;
    } catch (_) {
      // Endpoint optional/unavailable — fall through to map data.
    }

    // Reverse-geocode for prefill (lane/area/pincode) and, only if needed, city detection.
    final geo = await repo.reverseGeocode(lat, lng);

    // Prefer the city the user already chose; only auto-detect when none is selected — this
    // avoids the false "couldn't find a Link Local city" after they picked a city manually.
    final City? city = _city ??
        (hit != null ? (_cityById(hit.cityId) ?? _cityByName(hit.city)) : null) ??
        _cityByName(geo.city);

    if (city == null) {
      final detected = geo.city;
      setState(() => _error = (detected != null && detected.isNotEmpty)
          ? "Link Local isn't available in $detected yet. Please pick a city from the list."
          : "We couldn't find a Link Local city at your location. Please pick your city.");
      return;
    }

    _city = city;
    _state = city.state ?? geo.state ?? _state;
    _picked = LatLng(lat, lng);
    _prefill
      // GPS / map pin never fills the building — we can't know the exact complex.
      ..['building'] = ''
      ..['lane1'] = hit?.lane1 ?? geo.lane1 ?? ''
      ..['lane2'] = hit?.lane2 ?? geo.locality ?? ''
      ..['area'] = hit?.area ?? geo.area ?? geo.locality ?? ''
      ..['suburb'] = hit?.suburb ?? geo.suburb ?? ''
      ..['pincode'] = hit?.pincode ?? geo.pincode ?? '';
    await _loadFields();
    if (mounted) _openConfirmSheet();
  }

  Future<void> _pickOnMap() async {
    // City is mandatory before a manual map pin (GPS path handles detection on its own).
    if (_city == null) {
      setState(() => _error = 'Select your city first, or tap "Use Current Location".');
      return;
    }
    final geo = await Navigator.of(context).push<GeoAddress>(
      // Reopen on the existing pin so a small correction doesn't restart the map.
      MaterialPageRoute(builder: (_) => AddressMapScreen(initial: _picked)),
    );
    if (geo == null) return;
    setState(() => _error = null);
    await _resolveLocation(geo.latitude, geo.longitude);
  }

  Future<void> _next() async {
    if (_city == null) {
      setState(() => _error = 'Please select your city');
      return;
    }
    if (_fieldCtrls.isEmpty) await _loadFields();
    if (mounted) _openConfirmSheet();
  }

  Future<void> _submit(StateSetter setSheet) async {
    if (_city == null) {
      setSheet(() => _error = 'Please select your city');
      return;
    }
    // Required-field validation per the city's config.
    for (final f in _fields) {
      if (f.isRequired && (_fieldCtrls[f.fieldKey]?.text.trim().isEmpty ?? true)) {
        setSheet(() => _error = '${f.label} is required');
        return;
      }
    }
    setSheet(() => _error = null);
    String v(String key) => _fieldCtrls[key]?.text.trim() ?? '';

    final ordered = _fields.map((f) => v(f.fieldKey)).where((s) => s.isNotEmpty).toList();
    // State is derived from the city (never user-entered) so it can never disagree with it.
    final full = [...ordered, _city!.name, ?_state].join(', ');

    try {
      await ref.read(addressRepositoryProvider).createAddress(
            cityId: _city!.id,
            fullAddress: full,
            flatWing: v('flat_wing'),
            apartment: v('building'),
            lane1: v('lane1'),
            lane2: v('lane2'),
            areaName: v('area').isNotEmpty ? v('area') : v('lane2'),
            suburb: v('suburb'),
            pincode: v('pincode'),
            latitude: _picked?.latitude,
            longitude: _picked?.longitude,
          );
      if (mounted) {
        Navigator.pop(context);
        context.go(Routes.verifyAddress);
      }
    } catch (e) {
      setSheet(() => _error = e.toString());
    }
  }

  void _openConfirmSheet() {
    // Reaching the sheet means we have a valid, confirmable address — clear any earlier
    // banner (e.g. a failed "Use Current Location" attempt) so it doesn't show stale here.
    setState(() => _error = null);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true, // keep the header clear of the status bar / dynamic island
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Grabber + back button so the user can return to the address screen.
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(ctx),
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.arrow_back, color: AppColors.ink),
                      ),
                    ),
                    Expanded(
                      child: Center(child: Text('Confirm your Address', style: Theme.of(ctx).textTheme.headlineSmall)),
                    ),
                    const SizedBox(width: 32), // balances the back icon so the title stays centred
                  ],
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: 'This will help us connect you to your '),
                    TextSpan(text: 'Local', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                    TextSpan(text: ' network'),
                  ]), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                ),
                const SizedBox(height: 20),
                // Dynamic fields from the city's configured form format.
                for (final f in _fields) ...[
                  _label(f.label, required: f.isRequired),
                  PillField(controller: _fieldCtrls[f.fieldKey]!, hint: f.label),
                  const SizedBox(height: 16),
                ],
                // City + State are determined from the chosen city / detected location and
                // are locked here so they're always populated and can never disagree
                // (e.g. Delhi shown for a Mumbai address). Change the city on the previous
                // screen if it's wrong.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('City', required: true),
                          _lockedField(_city?.name),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('State'),
                          _lockedField(_state),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[const SizedBox(height: 14), ErrorBanner(message: _error!)],
                const SizedBox(height: 22),
                PrimaryButton(label: 'Confirm', onPressed: () => _submit(setSheet)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dropDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      );

  /// A read-only, populated field (used for the locked City/State in the confirm sheet).
  Widget _lockedField(String? value) {
    final empty = value == null || value.isEmpty;
    return Container(
      height: 52,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              empty ? '—' : value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: empty ? AppColors.textMuted : AppColors.ink,
              ),
            ),
          ),
          const Icon(Icons.lock_outline, size: 15, color: AppColors.textMuted),
        ],
      ),
    );
  }

  Widget _label(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RichText(
          text: TextSpan(
            text: text,
            style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 15),
            children: required ? [const TextSpan(text: ' *', style: TextStyle(color: AppColors.error))] : null,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final citiesAsync = ref.watch(citiesProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const AuthHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  const AuthHeading(title: 'Connect Locally', highlight: 'Locally', subtitle: 'Enter your address to connect locally'),
                  const SizedBox(height: 22),
                  _label('City', required: true),
                  citiesAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => const Text('Failed to load cities', style: TextStyle(color: AppColors.error)),
                    data: (cities) => DropdownButtonFormField<City>(
                      initialValue: cities.contains(_city) ? _city : null,
                      isExpanded: true,
                      decoration: _dropDecoration('Select your city'),
                      items: cities.map((c) => DropdownMenuItem(value: c, child: Text(c.label))).toList(),
                      onChanged: (c) {
                        setState(() {
                          _city = c;
                          _state = c?.state ?? _state;
                          _error = null; // a manual city choice clears the "not available" notice
                        });
                        _loadFields();
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(label: 'Use Current Location', loading: _locating, icon: Icons.my_location, onPressed: _useCurrentLocation),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.ink, thickness: 1)),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('Or', style: Theme.of(context).textTheme.titleMedium)),
                      const Expanded(child: Divider(color: AppColors.ink, thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  PillField(controller: _search, hint: 'Search your lane / area / locality', icon: Icons.location_on_outlined),
                  _SearchListener(controller: _search, onChanged: _onSearchChanged),
                  if (_searching) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                  ..._suggestions.map((s) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          (s.complex != null && s.complex!.isNotEmpty) ? Icons.apartment : Icons.location_on_outlined,
                          color: AppColors.primary,
                        ),
                        title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _applySuggestion(s),
                      )),
                  const SizedBox(height: 16),
                  _MapPreview(picked: _picked, onTap: _pickOnMap),
                  if (_error != null) ...[const SizedBox(height: 14), ErrorBanner(message: _error!)],
                  const SizedBox(height: 20),
                  PrimaryButton(label: 'Next', loading: _fieldsLoading, onPressed: _next),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bridges PillField (a plain TextField) to an onChanged callback.
class _SearchListener extends StatefulWidget {
  const _SearchListener({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  @override
  State<_SearchListener> createState() => _SearchListenerState();
}

class _SearchListenerState extends State<_SearchListener> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_listen);
  }

  void _listen() => widget.onChanged(widget.controller.text);

  @override
  void dispose() {
    widget.controller.removeListener(_listen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.picked, required this.onTap});
  final LatLng? picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final center = picked ?? const LatLng(19.2503, 72.9780);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IgnorePointer(
                child: FlutterMap(
                  // Re-create the map when the pin changes so it re-centers on the picked
                  // location (e.g. after choosing a search suggestion with coordinates).
                  key: ValueKey(picked),
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: picked != null ? 16 : 14,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.sentellent.link_local',
                    ),
                    if (picked != null)
                      MarkerLayer(markers: [
                        Marker(point: picked!, width: 40, height: 40, child: const Icon(Icons.location_on, color: AppColors.primary, size: 40)),
                      ]),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, size: 18, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Tap to pick on map', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
