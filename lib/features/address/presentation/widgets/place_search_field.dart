import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/location/place_session_token.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/address_models.dart';
import '../../data/address_repository.dart';

/// A place picked from search: its map position and Google id alongside the text.
class PickedPlace {
  const PickedPlace({required this.latitude, required this.longitude, this.googlePlaceId});
  final double latitude;
  final double longitude;
  final String? googlePlaceId;
}

/// A location text field with place search: suggestions from Google (restricted to
/// [cityId]'s service area) as the member types, plus a "Use … as typed" row for spots
/// Google doesn't know ("Tower B terrace").
///
/// [controller] always holds the location text. [onChanged] reports the map position when a
/// suggestion is picked, and null once the text is typed or edited by hand — so a stale
/// position never outlives the text it belonged to. Without a [cityId] it is a plain field.
class PlaceSearchField extends ConsumerStatefulWidget {
  const PlaceSearchField({
    super.key,
    required this.controller,
    required this.cityId,
    required this.onChanged,
    this.label = 'Location',
    this.validator,
  });

  final TextEditingController controller;
  final int? cityId;
  final ValueChanged<PickedPlace?> onChanged;
  final String label;

  /// Checked with the surrounding Form, like any other field.
  final FormFieldValidator<String>? validator;

  @override
  ConsumerState<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends ConsumerState<PlaceSearchField> {
  final _focus = FocusNode();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = [];
  bool _searching = false;
  bool _open = false;
  int _seq = 0;
  String? _session;

  /// The text as last set by a pick, so the listener can tell a pick from typing.
  String? _pickedText;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) setState(() => _open = false);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _onTyped(String text) {
    if (text == _pickedText) return;
    _pickedText = null;
    widget.onChanged(null); // hand-edited text no longer matches any picked position
    _debounce?.cancel();
    final term = text.trim();
    if (widget.cityId == null || term.length < 3) {
      _seq++;
      setState(() {
        _suggestions = [];
        _searching = false;
        _open = term.isNotEmpty;
      });
      return;
    }
    setState(() => _open = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(term));
  }

  Future<void> _search(String term) async {
    final seq = ++_seq;
    setState(() => _searching = true);
    List<PlaceSuggestion> results;
    try {
      results = await ref
          .read(addressRepositoryProvider)
          .autocomplete(term, sessionToken: _session ??= newPlaceSessionToken(), cityId: widget.cityId!);
    } catch (_) {
      results = []; // search is a convenience; typing still works
    }
    if (!mounted || seq != _seq) return;
    setState(() {
      _suggestions = results;
      _searching = false;
    });
  }

  Future<void> _pick(PlaceSuggestion s) async {
    final session = _session;
    _session = null; // details closes the Google session
    final text = [s.primaryText, s.secondaryText].whereType<String>().where((t) => t.isNotEmpty).join(', ');
    _set(text);
    _focus.unfocus();
    try {
      final place = await ref.read(addressRepositoryProvider).placeDetails(s.placeId, sessionToken: session);
      if (!mounted || widget.controller.text != text) return;
      widget.onChanged(
        place == null
            ? null
            : PickedPlace(latitude: place.geo.latitude, longitude: place.geo.longitude, googlePlaceId: s.placeId),
      );
    } catch (_) {
      // The text is kept; it just has no map position.
    }
  }

  void _useAsTyped() {
    widget.onChanged(null);
    _focus.unfocus();
    setState(() => _open = false);
  }

  void _set(String text) {
    _pickedText = text;
    _seq++;
    widget.controller.text = text;
    setState(() {
      _open = false;
      _suggestions = [];
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final typed = widget.controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focus,
          onChanged: _onTyped,
          validator: widget.validator,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: widget.label,
            errorMaxLines: 2,
            hintText: widget.cityId == null ? null : 'Search a place, or type it',
            suffixIcon: const Icon(Icons.search, color: AppColors.textMuted),
          ),
        ),
        if (_open && typed.isNotEmpty)
          // Part of the field's tap region, so tapping a suggestion doesn't count as tapping
          // away (which would close the list before the tap lands).
          TextFieldTapRegion(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              // A Material (not a coloured box) so the rows' tap ripples show.
              child: Material(
                color: AppColors.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_searching) const LinearProgressIndicator(minHeight: 2),
                    ..._suggestions.map(
                      (s) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined, color: AppColors.primary),
                        title: Text(s.primaryText, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: s.secondaryText == null
                            ? null
                            : Text(s.secondaryText!, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _pick(s),
                      ),
                    ),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.edit_location_alt_outlined, color: AppColors.textSecondary),
                      title: Text('Use "$typed" as typed'),
                      onTap: _useAsTyped,
                    ),
                    // Google's terms require attribution wherever its suggestions show without a map.
                    if (_suggestions.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(0, 0, 12, 6),
                        child: Text(
                          'Powered by Google',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
