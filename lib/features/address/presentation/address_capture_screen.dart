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

const _indianStates = [
  'Maharashtra', 'Delhi', 'Karnataka', 'Tamil Nadu', 'Telangana', 'Gujarat',
  'West Bengal', 'Rajasthan', 'Uttar Pradesh', 'Kerala', 'Punjab', 'Haryana',
];

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

  Timer? _debounce;
  List<ComplexSuggestion> _suggestions = [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  City? _cityByName(String? name) {
    if (name == null) return null;
    final cities = ref.read(citiesProvider).asData?.value ?? [];
    for (final c in cities) {
      if (c.name.toLowerCase() == name.toLowerCase()) return c;
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
        if (mounted) setState(() => _suggestions = res.complexes);
      } catch (_) {
        if (mounted) setState(() => _suggestions = []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _applySuggestion(ComplexSuggestion s) async {
    _prefill
      ..['building'] = s.apartment
      ..['lane1'] = s.lane1 ?? ''
      ..['area'] = s.locality
      ..['lane2'] = s.locality
      ..['pincode'] = s.pincode ?? '';
    _city = _cityByName(s.city) ?? _city;
    _state = _city?.state ?? _state;
    setState(() {
      _suggestions = [];
      _search.text = s.apartment;
    });
    await _loadFields();
    if (mounted) _openConfirmSheet();
  }

  Future<void> _applyGeo(GeoAddress geo) async {
    _picked = LatLng(geo.latitude, geo.longitude);
    _prefill
      ..['lane1'] = geo.lane1 ?? ''
      ..['area'] = geo.locality ?? geo.area ?? ''
      ..['suburb'] = geo.suburb ?? ''
      ..['pincode'] = geo.pincode ?? '';
    _city = _cityByName(geo.city) ?? _city;
    _state = geo.state ?? _city?.state ?? _state;
    await _loadFields();
    if (mounted) _openConfirmSheet();
  }

  Future<void> _useCurrentLocation() async {
    if (_city == null) {
      setState(() => _error = 'Please select your city first');
      return;
    }
    setState(() => _error = null);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw 'Location services are off.';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Location permission denied.';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final geo = await ref.read(addressRepositoryProvider).reverseGeocode(pos.latitude, pos.longitude);
      await _applyGeo(geo);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pickOnMap() async {
    final geo = await Navigator.of(context).push<GeoAddress>(
      MaterialPageRoute(builder: (_) => const AddressMapScreen()),
    );
    if (geo != null) await _applyGeo(geo);
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                Center(child: Text('Confirm your Address', style: Theme.of(ctx).textTheme.headlineSmall)),
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
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('City', required: true),
                          Container(
                            height: 52,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.field,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(_city?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('State'),
                          DropdownButtonFormField<String>(
                            initialValue: _indianStates.contains(_state) ? _state : null,
                            isExpanded: true,
                            decoration: _dropDecoration('State'),
                            items: _indianStates.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (s) => setSheet(() => _state = s),
                          ),
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
                      initialValue: _city,
                      isExpanded: true,
                      decoration: _dropDecoration('Select your city'),
                      items: cities.map((c) => DropdownMenuItem(value: c, child: Text(c.label))).toList(),
                      onChanged: (c) {
                        setState(() {
                          _city = c;
                          _state = c?.state ?? _state;
                        });
                        _loadFields();
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(label: 'Use Current Location', loading: _fieldsLoading, icon: Icons.my_location, onPressed: _useCurrentLocation),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.ink, thickness: 1)),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('Or', style: Theme.of(context).textTheme.titleMedium)),
                      const Expanded(child: Divider(color: AppColors.ink, thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  PillField(controller: _search, hint: 'Enter your Address e.g. your Building name', icon: Icons.location_on_outlined),
                  _SearchListener(controller: _search, onChanged: _onSearchChanged),
                  if (_searching) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                  ..._suggestions.map((s) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.apartment, color: AppColors.primary),
                        title: Text(s.apartment, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([s.lane1, s.locality, s.pincode].whereType<String>().join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 14,
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
