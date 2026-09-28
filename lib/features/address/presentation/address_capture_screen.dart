import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/location/location_models.dart';
import '../../../core/location/place_session_token.dart';
import '../../../core/validation/locality_rules.dart';
import '../../../core/location/location_providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/auth_header.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../feed/data/feed_repository.dart';
import '../../home/data/home_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../reference/reference_models.dart';
import '../../reference/reference_repository.dart';
import '../data/address_models.dart';
import '../data/address_repository.dart';
import 'address_map_screen.dart';
import 'address_proof_screen.dart';
import '../../../core/navigation/push_guard.dart';

/// Which way a location was captured — the wording of a city mismatch depends on it.
enum _Origin { search, currentLocation, map }

/// Why a location can't be used with the selected city, and how to fix it.
class _CityIssue {
  const _CityIssue(this.message, {this.switchTo, this.retry});
  final String message;

  /// Another served city the location is in, offered as a one-tap switch.
  final City? switchTo;

  /// Re-runs the rejected location once [switchTo] is selected.
  final Future<void> Function()? retry;
}

class AddressCaptureScreen extends ConsumerStatefulWidget {
  const AddressCaptureScreen({super.key, this.editing = false});

  /// Changing an existing address from the profile, rather than capturing the first one
  /// during onboarding: starts on the member's current city, confirms a move to another
  /// city, and then goes to proof upload for the new address (verification belongs to an
  /// address, so a changed one starts unverified) instead of continuing onboarding.
  final bool editing;

  @override
  ConsumerState<AddressCaptureScreen> createState() => _AddressCaptureScreenState();
}

class _AddressCaptureScreenState extends ConsumerState<AddressCaptureScreen> {
  final _search = TextEditingController();
  City? _city;
  String? _state;
  LatLng? _picked;
  /// How the pin was captured, carried through to the saved address so a bad
  /// pin can be traced back to the fix that produced it.
  LocationFix? _fix;
  String? _placeId;
  /// Set when the fix behind a prefill was too coarse to trust, shown in the
  /// confirm sheet so the member can correct it before saving.
  String? _accuracyWarning;

  /// Best fix from the background warm-up started when this screen opened.
  LocationFix? _warmFix;
  StreamSubscription<LocationFix>? _warmUp;

  /// Past this the warm fix is discarded rather than trusted — the member may
  /// have moved between opening the screen and tapping the button.
  static const _warmFixMaxAge = Duration(seconds: 45);

  /// How far a curated Address Master locality may be from the pin and still be
  /// trusted for a given field. `nearbyMaster` searches a 2 km radius, which is
  /// the right net for "which city is this" but far too wide for "which lane is
  /// this" — 2 km crosses several suburbs and more than one pincode in Thane or
  /// Mumbai. Beyond each radius the field falls through to the geocoder rather
  /// than inheriting a stranger's address.
  static const _laneTrustKm = 0.15;
  static const _areaTrustKm = 0.5;

  // Per-city address-form config + a controller per field key.
  List<CityAddressField> _fields = [];
  final Map<String, TextEditingController> _fieldCtrls = {};
  final Map<String, String> _prefill = {};
  bool _fieldsLoading = false;
  bool _locating = false;

  Timer? _debounce;
  List<MasterSuggestion> _suggestions = [];
  /// Google place suggestions, shown after the curated ones.
  List<PlaceSuggestion> _places = [];
  bool _searching = false;
  /// Set when a search came back empty from both sources, so the member is told
  /// instead of being left looking at nothing.
  bool _noMatches = false;
  String? _searchError;
  /// Bumped per search so a slow response can't overwrite a newer one.
  int _searchSeq = 0;
  /// The last search text acted on. The controller also notifies on cursor moves,
  /// and on the label written into the box when a suggestion is picked; neither
  /// should start a search.
  String _lastTerm = '';
  /// Google autocomplete session: one token from the first keystroke until a
  /// place is picked, so the whole search is billed as a single session.
  String? _placesSession;
  /// A location that doesn't belong to the selected city. Shown instead of
  /// prefilling the form, since the chosen city is authoritative.
  _CityIssue? _cityIssue;
  String? _error;

  /// The city of the address being replaced (edit mode), to spot a move between cities.
  int? _originalCityId;

  @override
  void initState() {
    super.initState();
    // Try to auto-select the city from the device location once cities have loaded.
    // Editing starts on the member's current city instead; auto-detection never
    // overrides a city that's already set, but still warms up GPS.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.editing) await _startFromCurrentCity();
      _autoDetectCity();
    });
  }

  Future<void> _startFromCurrentCity() async {
    try {
      await ref.read(citiesProvider.future);
      final profile = await ref.read(myProfileProvider.future);
      _originalCityId = profile.cityId;
      final city = _cityById(profile.cityId);
      if (city == null || !mounted || _city != null) return;
      setState(() {
        _city = city;
        _state = city.state ?? _state;
      });
      await _loadFields();
    } catch (_) {
      // The member can still pick the city themselves.
    }
  }

  /// Edit mode only: confirms moving to a different city, which changes the member's
  /// neighbourhood, groups and feed. True to go ahead.
  Future<bool> _confirmCityMove() async {
    final from = _cityById(_originalCityId);
    final to = _city;
    if (!widget.editing || from == null || to == null || from.id == to.id) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move to ${to.name}?'),
        content: Text('Moving from ${from.name} to ${to.name} changes your neighbourhood, '
            'groups and feed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Move to ${to.name}')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _warmUp?.cancel();
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
    final term = q.trim();
    if (term == _lastTerm) return;
    _lastTerm = term;
    _debounce?.cancel();
    if (term.length < 2) {
      setState(_clearSearchResults);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(term));
  }

  /// Searches the curated directory and Google together. Each source degrades on
  /// its own, so one failing never hides the other's results.
  Future<void> _runSearch(String term) async {
    final city = _city;
    if (city == null) return; // the search box is disabled until a city is chosen
    final seq = ++_searchSeq;
    final repo = ref.read(addressRepositoryProvider);
    final session = _placesSession ??= newPlaceSessionToken();
    setState(() => _searching = true);

    Object? failure;
    final directory = repo.searchDirectory(term, cityId: city.id).then((r) => r.localities).catchError((Object e) {
      failure = e;
      return <MasterSuggestion>[];
    });
    // Google needs a little more text before its suggestions are worth a request.
    final google = term.length < 3
        ? Future.value(<PlaceSuggestion>[])
        : repo
            .autocomplete(term, sessionToken: session, cityId: city.id)
            .catchError((Object e) {
            failure ??= e;
            return <PlaceSuggestion>[];
          });

    final localities = await directory;
    final places = await google;
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _searching = false;
      _suggestions = localities;
      _places = places;
      _noMatches = localities.isEmpty && places.isEmpty;
      _searchError = _noMatches ? failure?.toString() : null;
    });
  }

  /// Drops shown results and any search still in flight.
  void _clearSearchResults() {
    _searchSeq++;
    _debounce?.cancel();
    _suggestions = [];
    _places = [];
    _noMatches = false;
    _searchError = null;
    _searching = false;
  }

  /// Picks a Google suggestion: resolves it to coordinates + address fields, then
  /// runs the same flow as a map pin, so nearby curated localities still win.
  Future<void> _applyPlace(PlaceSuggestion s) async {
    // Fetching details closes the Google session; the next search starts a new one.
    final session = _placesSession;
    _placesSession = null;
    _lastTerm = s.primaryText;
    _search.text = s.primaryText;
    setState(() {
      _clearSearchResults();
      _error = null;
      _cityIssue = null;
      _searching = true;
    });
    try {
      final place = await ref.read(addressRepositoryProvider).placeDetails(s.placeId, sessionToken: session);
      if (!mounted) return;
      if (place == null) {
        setState(() => _error = "We couldn't load that place. Pin your location on the map instead.");
        return;
      }
      final geo = place.geo;
      await _resolveLocation(
        geo.latitude,
        geo.longitude,
        origin: _Origin.search,
        fix: LocationFix.fromPlace(latitude: geo.latitude, longitude: geo.longitude),
        geo: geo,
        building: place.isNamed ? s.primaryText : null,
        warning: place.isPrecise
            ? null
            : '"${s.primaryText}" is an area, not a single building, so the pin is only approximate. '
                'Check the details below, or pin your building on the map.',
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Applies a curated Address Master locality: sets city/state, prefills the lane/area/
  /// suburb/pincode fields, then opens the confirm sheet.
  Future<void> _applyMaster(MasterSuggestion s, {bool openSheet = true, LatLng? pin}) async {
    if (pin != null) {
      _picked = pin;
    } else if (s.latitude != null && s.longitude != null) {
      _picked = LatLng(s.latitude!, s.longitude!);
      // Curated coordinates supersede whatever the device last reported.
      _fix = LocationFix.fromMaster(latitude: s.latitude!, longitude: s.longitude!);
      _accuracyWarning = null;
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
    setState(_clearSearchResults);
    await _loadFields();
    if (openSheet && mounted) _openConfirmSheet();
  }

  Future<void> _applySuggestion(MasterSuggestion s) async {
    _lastTerm = s.title;
    _search.text = s.title;
    await _applyMaster(s);
  }

  /// The best fix the device can manage (throws a user-facing message on failure).
  ///
  /// Prefers the warm-up started when the screen opened: by the time the member
  /// has picked a city and reached this button it has usually converged, so they
  /// get an answer at once instead of waiting out a fresh 12-second acquisition.
  Future<LocationFix> _deviceFix() async {
    final warm = _warmFix;
    if (warm != null &&
        warm.isConfirmable &&
        DateTime.now().difference(warm.timestamp) <= _warmFixMaxAge) {
      return warm;
    }

    // Not good enough, or too old to trust. Acquire again — the GPS hardware is
    // already awake from the warm-up, so this converges far faster than cold.
    await _warmUp?.cancel();
    final service = ref.read(locationServiceProvider);
    final outcome = await service.ensurePermission();
    if (!outcome.canLocate) throw outcome.message ?? 'Could not get your location.';

    final fix = await service.acquireBest();
    if (fix == null) throw 'Could not get your location. Pin it on the map instead.';
    return fix;
  }

  /// Silent best-effort on screen load: detect the member's city, and keep the
  /// location stream running afterwards so that by the time they reach "Use
  /// Current Location" the fix has already converged. Never shows an error.
  Future<void> _autoDetectCity() async {
    try {
      await ref.read(citiesProvider.future); // ensure the city list is loaded
      final service = ref.read(locationServiceProvider);
      if (!(await service.ensurePermission()).canLocate) return;

      var cityResolved = false;
      _warmUp = service.acquire().listen(
        (fix) {
          _warmFix = fix;
          // Picking a city needs a suburb, not a doorstep, so fire on the first
          // real fix rather than waiting for the stream to converge.
          if (!cityResolved && fix.source != LocationSource.cached) {
            cityResolved = true;
            _detectCityFrom(fix);
          }
        },
        // If only a replayed last-known position ever arrived, it still beats
        // leaving the member with no city at all.
        onDone: () {
          final fix = _warmFix;
          if (!cityResolved && fix != null) _detectCityFrom(fix);
        },
        onError: (_) {},
        cancelOnError: true,
      );
    } catch (_) {
      // Ignore — the user can still select their city manually.
    }
  }

  /// Resolves a fix to a serviceable city and selects it, silently.
  Future<void> _detectCityFrom(LocationFix fix) async {
    // A city the member picked themselves is never overridden.
    if (_city != null) return;
    try {
      final repo = ref.read(addressRepositoryProvider);
      // A service area settles it without any lookups.
      var found = _servedCityAt(fix.latitude, fix.longitude);
      if (found == null) {
        // Curated master gives the serviceable city directly (best-effort; endpoint optional).
        MasterSuggestion? hit;
        try {
          final near = await repo.nearbyMaster(fix.latitude, fix.longitude);
          if (near.isNotEmpty) hit = near.first;
        } catch (_) {}
        // Fall back to map data (reverse geocoding) for the city name.
        final geoCity = hit == null ? (await repo.reverseGeocode(fix.latitude, fix.longitude)).city : null;
        found = _servedCityAt(fix.latitude, fix.longitude, hit: hit, geoCity: geoCity);
      }

      // Only auto-select when it's a city Link Local actually serves, and the
      // member hasn't picked one while we were looking.
      final city = found;
      if (city == null || !mounted || _city != null) return;
      setState(() {
        _city = city;
        _state = city.state ?? _state;
        _picked = LatLng(fix.latitude, fix.longitude);
        _fix = fix;
      });
      await _loadFields();
    } catch (_) {
      // Ignore — the user can still select their city manually.
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _error = null;
      _cityIssue = null;
      _locating = true;
    });
    try {
      final fix = await _deviceFix();
      await _resolveLocation(fix.latitude, fix.longitude, origin: _Origin.currentLocation, fix: fix);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Resolves a location to the address form. The selected city is authoritative: a
  /// location outside it is rejected with a [_CityIssue] (offering a switch when it is
  /// in another served city) instead of being prefilled. Only "Use Current Location"
  /// can arrive with no city selected; the city is then detected from the location.
  ///
  /// Callers that already resolved the location pass its [geo] (saving a reverse
  /// geocode); a picked named place passes its [building] name, and a [warning] when
  /// its pin is only an area's centre.
  Future<void> _resolveLocation(
    double lat,
    double lng, {
    required _Origin origin,
    LocationFix? fix,
    GeoAddress? geo,
    String? building,
    String? warning,
  }) async {
    final repo = ref.read(addressRepositoryProvider);

    // 1) Curated Address Master within 2 km → the serviceable city directly (best-effort).
    MasterSuggestion? hit;
    // Every entry sharing the nearest one's exact distance. The master stores a
    // single representative coordinate per locality rather than per lane, so the
    // "nearest" entry is routinely one of a large tie — around eight on average
    // in the current data, and up to thirteen. Which one arrives first is
    // arbitrary, so any field they disagree on cannot be inferred from the pin.
    var tied = const <MasterSuggestion>[];
    try {
      final near = await repo.nearbyMaster(lat, lng);
      if (near.isNotEmpty) {
        hit = near.first;
        final nearest = hit.distanceKm;
        tied = nearest == null
            ? [hit]
            : near.where((m) => ((m.distanceKm ?? nearest) - nearest).abs() < 0.001).toList();
      }
    } catch (_) {
      // Endpoint optional/unavailable — fall through to map data.
    }

    // Reverse-geocode for prefill (lane/area/pincode) and city checks.
    final resolved = geo ?? await repo.reverseGeocode(lat, lng);
    if (!mounted) return;

    final selected = _city;
    if (selected == null) {
      final detected = _servedCityAt(lat, lng, hit: hit, geoCity: resolved.city);
      if (detected == null) {
        final name = resolved.city;
        setState(() => _error = (name != null && name.isNotEmpty)
            ? "Link Local isn't available in $name yet. Please pick a city from the list."
            : "We couldn't find a Link Local city at your location. Please pick your city.");
        return;
      }
      _city = detected;
      _state = detected.state ?? resolved.state ?? _state;
    } else {
      final issue = _cityIssueFor(
        selected,
        lat,
        lng,
        origin: origin,
        fix: fix,
        hit: hit,
        geoCity: resolved.city,
        retry: () => _resolveLocation(
          lat,
          lng,
          origin: origin,
          fix: fix,
          geo: resolved,
          building: building,
          warning: warning,
        ),
      );
      if (issue != null) {
        setState(() => _cityIssue = issue);
        return;
      }
    }
    // Curated neighbours from across the city line can't describe this address.
    if (hit != null && hit.cityId != _city!.id) {
      hit = null;
      tied = const [];
    }
    _cityIssue = null;
    _picked = LatLng(lat, lng);
    _fix = fix ?? _fix;
    _placeId = resolved.googlePlaceId ?? _placeId;
    // Converge-then-warn applies on this path too: the member never sees the map
    // here, so the sheet is the only place left to tell them the fix was coarse.
    final f = _fix;
    _accuracyWarning = warning ??
        ((f != null && !f.isConfirmable)
        ? 'Your location was only accurate to ${f.accuracyLabel ?? 'an unknown radius'}. '
            'Check the details below, or pin your building on the map.'
        : null);
    // Two independent guards before a curated value is trusted. Distance: a
    // locality 1.9 km away is still the nearest, but its lane is not the
    // member's lane, and an unknown distance counts as too far. Agreement: the
    // tied candidates must all say the same thing. Whatever fails a guard falls
    // through to the geocoder rather than inheriting a neighbour's address.
    // City resolution above deliberately keeps using the full 2 km.
    final km = hit?.distanceKm;
    final laneOk = km != null && km <= _laneTrustKm;
    final areaOk = km != null && km <= _areaTrustKm;

    _prefill
      // GPS / map pin never fills the building — we can't know the exact complex.
      // A searched named place (a society, a farm) is the exception: the member picked it.
      ..['building'] = building ?? ''
      ..['lane1'] = (laneOk ? _agreed(tied, (m) => m.lane1) : null) ?? resolved.lane1 ?? ''
      ..['lane2'] = (laneOk ? _agreed(tied, (m) => m.lane2) : null) ?? resolved.locality ?? ''
      ..['area'] = (areaOk ? _agreed(tied, (m) => m.area) : null) ?? resolved.area ?? resolved.locality ?? ''
      ..['suburb'] = (areaOk ? _agreed(tied, (m) => m.suburb) : null) ?? resolved.suburb ?? ''
      ..['pincode'] = (areaOk ? _agreed(tied, (m) => m.pincode) : null) ?? resolved.pincode ?? '';
    await _loadFields();
    if (mounted) _openConfirmSheet();
  }

  /// The served city a point falls in: by service area first, then — for cities
  /// without one — the nearest curated locality's city or the geocoder's city name.
  /// A city whose service area excludes the point is never returned.
  City? _servedCityAt(double lat, double lng, {MasterSuggestion? hit, String? geoCity}) {
    for (final c in _cities) {
      if (c.contains(lat, lng) == true) return c;
    }
    bool plausible(City? c) => c != null && c.contains(lat, lng) != false;
    final byHit = hit == null ? null : (_cityById(hit.cityId) ?? _cityByName(hit.city));
    if (plausible(byHit)) return byHit;
    final byName = _cityByName(geoCity);
    return plausible(byName) ? byName : null;
  }

  /// Null when the location belongs to [city]; otherwise what's wrong, worded for
  /// how it was captured, with a switch offered when it is in another served city.
  _CityIssue? _cityIssueFor(
    City city,
    double lat,
    double lng, {
    required _Origin origin,
    required Future<void> Function() retry,
    LocationFix? fix,
    MasterSuggestion? hit,
    String? geoCity,
  }) {
    final name = city.name;
    final inArea = city.contains(lat, lng);

    bool inCity;
    if (inArea != null) {
      inCity = inArea;
    } else {
      // No service area: judge by name. A location nothing can name is let
      // through — the backend has nothing to judge it by either.
      final named = (hit != null ? _cityById(hit.cityId) : null) ?? _cityByName(geoCity);
      inCity = named?.id == city.id || (named == null && (geoCity == null || geoCity.isEmpty));
    }

    if (inCity) {
      // A GPS fix whose error circle crosses the edge can't prove it's inside.
      final acc = fix?.accuracyM;
      final d = city.distanceFromCenterKm(lat, lng);
      final measured = fix != null && fix.source != LocationSource.manualPin && fix.source != LocationSource.place;
      if (origin == _Origin.currentLocation && measured && acc != null && d != null && d + acc / 1000 > city.radiusKm!) {
        return _CityIssue("Your location isn't precise enough to confirm you're in $name. "
            'Pin your building on the map instead.');
      }
      return null;
    }

    final other = _servedCityAt(lat, lng, hit: hit, geoCity: geoCity);
    if (other != null && other.id != city.id) {
      return _CityIssue(
        switch (origin) {
          _Origin.search => 'That address is in ${other.name}, not $name.',
          _Origin.currentLocation => "You're currently in ${other.name}, not $name. "
              'To register an address in $name, search for it or pin it on the map.',
          _Origin.map => 'That pin is in ${other.name}, not $name.',
        },
        switchTo: other,
        retry: retry,
      );
    }
    return _CityIssue(switch (origin) {
      _Origin.search => 'That address is outside $name. Pick an address in $name, or change your city.',
      _Origin.currentLocation => "Your current location is outside $name. If you're registering your "
          '$name address from elsewhere, search for it or pin it on the map.',
      _Origin.map => 'That pin is outside $name. Move it into $name, or change your city.',
    });
  }

  /// Takes the switch offered by a [_CityIssue], then re-applies the location.
  Future<void> _switchCity(_CityIssue issue) async {
    final city = issue.switchTo!;
    setState(() {
      _city = city;
      _state = city.state ?? _state;
      _cityIssue = null;
    });
    await issue.retry?.call();
  }

  /// A manual city change: anything captured for the previous city is dropped,
  /// so its address can't be saved under the new one.
  void _onCityChanged(City? city) {
    setState(() {
      _city = city;
      _state = city?.state ?? _state;
      _error = null; // a manual city choice clears the "not available" notice
      _cityIssue = null;
      _prefill.clear();
      _picked = null;
      _fix = null;
      _placeId = null;
      _accuracyWarning = null;
      _placesSession = null;
      _lastTerm = '';
      _search.clear();
      _clearSearchResults();
    });
    _loadFields();
  }

  /// The one value every tied candidate agrees on, or null when they disagree —
  /// disagreement being the signal that this field cannot be read off the pin.
  static String? _agreed(
    List<MasterSuggestion> tied,
    String? Function(MasterSuggestion) field,
  ) {
    final values = tied.map(field).whereType<String>().where((v) => v.isNotEmpty).toSet();
    return values.length == 1 ? values.first : null;
  }

  Future<void> _pickOnMap() async {
    // City is mandatory before a manual map pin (GPS path handles detection on its own).
    if (_city == null) {
      setState(() => _error = 'Select your city first, or tap "Use Current Location".');
      return;
    }
    final result = await context.pushPage<MapPinResult>(
      // Reopen on the existing pin so a small correction doesn't restart the map.
      MaterialPageRoute(builder: (_) => AddressMapScreen(initial: _picked, city: _city)),
    );
    if (result == null) return;
    setState(() {
      _error = null;
      _cityIssue = null;
    });
    await _resolveLocation(
      result.fix.latitude,
      result.fix.longitude,
      origin: _Origin.map,
      fix: result.fix,
      geo: result.address, // the map already reverse-geocoded the pin
    );
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
      final text = _fieldCtrls[f.fieldKey]?.text ?? '';
      if (f.isRequired && text.trim().isEmpty) {
        setSheet(() => _error = '${f.label} is required');
        return;
      }
      // Same length/character rules the backend applies to addresses and localities.
      final problem = addressFieldError(f.fieldKey, f.label, text);
      if (problem != null) {
        setSheet(() => _error = problem);
        return;
      }
    }
    setSheet(() => _error = null);
    String v(String key) => normalizeLocality(_fieldCtrls[key]?.text ?? '');

    final ordered = _fields.map((f) => v(f.fieldKey)).where((s) => s.isNotEmpty).toList();
    // State is derived from the city (never user-entered) so it can never disagree with it.
    final full = [...ordered, _city!.name, ?_state].join(', ');

    if (!await _confirmCityMove()) return;
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
            accuracyM: _fix?.accuracyM,
            locationSource: _fix?.sourceWireValue,
            googlePlaceId: _placeId,
          );
      if (!mounted) return;
      Navigator.pop(context); // the confirm sheet
      if (widget.editing) {
        // Everything location-scoped now describes the old address.
        ref.invalidate(myProfileProvider);
        ref.invalidate(myAddressProofProvider);
        ref.invalidate(homeFeedProvider);
        ref.invalidate(feedProvider);
        // Straight on to proving the new address; that screen returns to the profile.
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AddressProofScreen()));
      } else {
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
                if (_accuracyWarning != null) ...[
                  ErrorBanner(message: _accuracyWarning!, tone: BannerTone.warning),
                  const SizedBox(height: 18),
                ],
                // Dynamic fields from the city's configured form format.
                for (final f in _fields) ...[
                  _label(f.label, required: f.isRequired),
                  PillField(
                    controller: _fieldCtrls[f.fieldKey]!,
                    hint: f.label,
                    maxLength: addressFieldMaxLength(f.fieldKey),
                    keyboardType: f.fieldKey == 'pincode' ? TextInputType.number : null,
                    inputFormatters: f.fieldKey == 'pincode' ? [FilteringTextInputFormatter.digitsOnly] : null,
                  ),
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
      // Onboarding has no way back; editing from the profile does.
      appBar: widget.editing ? AppBar(title: const Text('Change address')) : null,
      body: Column(
        children: [
          if (!widget.editing) const AuthHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  widget.editing
                      ? const AuthHeading(
                          title: 'Your new Address',
                          highlight: 'Address',
                          subtitle: "You'll upload proof for it next, as your address is verified",
                        )
                      : const AuthHeading(title: 'Connect Locally', highlight: 'Locally', subtitle: 'Enter your address to connect locally'),
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
                      onChanged: _onCityChanged,
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
                  PillField(
                    controller: _search,
                    enabled: _city != null,
                    hint: _city == null ? 'Select your city first' : 'Search in ${_city!.name}',
                    icon: Icons.location_on_outlined,
                  ),
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
                  ..._places.map((p) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.place_outlined, color: AppColors.primary),
                        title: Text(p.primaryText, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: p.secondaryText == null
                            ? null
                            : Text(p.secondaryText!, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _applyPlace(p),
                      )),
                  // Google's terms require attribution wherever its suggestions show without a map.
                  if (_places.isNotEmpty)
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text('Powered by Google', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ),
                  if (_noMatches && !_searching)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _searchError ??
                                  'No matches in ${_city?.name ?? 'your city'}. '
                                      'Try a different spelling, or pin it on the map.',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                          TextButton(onPressed: _pickOnMap, child: const Text('Pin on map')),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  _MapPreview(picked: _picked, onTap: _pickOnMap),
                  if (_cityIssue case final issue?) ...[
                    const SizedBox(height: 14),
                    ErrorBanner(
                      message: issue.message,
                      action: issue.switchTo == null
                          ? null
                          : TextButton(
                              onPressed: () => _switchCity(issue),
                              child: Text('Switch to ${issue.switchTo!.name}'),
                            ),
                    ),
                  ],
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
                child: GoogleMap(
                  // Re-create the map when the pin changes so it re-centers on the picked
                  // location (e.g. after choosing a search suggestion with coordinates).
                  key: ValueKey(picked),
                  initialCameraPosition: CameraPosition(
                    target: center,
                    zoom: picked != null ? 16 : 14,
                  ),
                  // A bitmap-backed map on Android: this is a static thumbnail, so
                  // there is no reason to spin up a fully interactive map view.
                  liteModeEnabled: true,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  myLocationButtonEnabled: false,
                  markers: picked == null
                      ? const {}
                      : {Marker(markerId: const MarkerId('picked'), position: picked!)},
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
