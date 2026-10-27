import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../services/data/service_profile_repository.dart';

/// Bottom sheet letting the resident pick a different area within their own city — re-scopes
/// the Home feed to that area (see `homeScopeProvider.setArea`). Single-select; Home's section
/// headers use [showAreaMultiSheet], and SP service areas the full-screen `AreaPickerScreen`.
Future<SelectedArea?> showAreaPickerSheet(BuildContext context, {required int? cityId}) async =>
    (await _show(context, cityId: cityId))?.area;

/// What [showAreaScopeSheet] picked: one area, or the whole city when [area] is null.
class AreaScopeChoice {
  const AreaScopeChoice(this.area);
  final SelectedArea? area;
  bool get isWholeCity => area == null;
}

/// [showAreaPickerSheet] with a leading "All of [cityName]" row, so a narrowed view can be
/// widened back to the city. Ticks the current choice: [selectedAreaId], or the city row
/// when [wholeCitySelected]. Null when dismissed.
Future<AreaScopeChoice?> showAreaScopeSheet(
  BuildContext context, {
  required int? cityId,
  required String cityName,
  int? selectedAreaId,
  bool wholeCitySelected = false,
}) =>
    _show(
      context,
      cityId: cityId,
      wholeCityName: cityName,
      selectedAreaId: selectedAreaId,
      wholeCitySelected: wholeCitySelected,
    );

Future<AreaScopeChoice?> _show(
  BuildContext context, {
  required int? cityId,
  String? wholeCityName,
  int? selectedAreaId,
  bool wholeCitySelected = false,
}) {
  return showModalBottomSheet<AreaScopeChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AreaPickerSheet(
      cityId: cityId,
      wholeCityName: wholeCityName,
      selectedAreaId: selectedAreaId,
      wholeCitySelected: wholeCitySelected,
    ),
  );
}

class _AreaPickerSheet extends ConsumerStatefulWidget {
  const _AreaPickerSheet({
    required this.cityId,
    this.wholeCityName,
    this.selectedAreaId,
    this.wholeCitySelected = false,
  });
  final int? cityId;

  /// When set, a leading "All of …" row that picks the whole city.
  final String? wholeCityName;
  final int? selectedAreaId;
  final bool wholeCitySelected;

  @override
  ConsumerState<_AreaPickerSheet> createState() => _AreaPickerSheetState();
}

class _AreaPickerSheetState extends ConsumerState<_AreaPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<SelectedArea> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final areas = await ref.read(serviceProfileRepositoryProvider).searchAreas(q: q, cityId: widget.cityId);
      if (mounted) {
        setState(() {
          _results = areas;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text('Choose an area', style: Theme.of(context).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: _onQueryChanged,
                          decoration: const InputDecoration(
                            hintText: 'Search area or pincode',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (widget.wholeCityName != null) ...[
                ListTile(
                  leading: const Icon(Icons.location_city_outlined, color: AppColors.primary),
                  title: Text('All of ${widget.wholeCityName}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: widget.wholeCitySelected ? const Icon(Icons.check, color: AppColors.primary) : null,
                  onTap: () => Navigator.of(context).pop(const AreaScopeChoice(null)),
                ),
                const Divider(height: 1, indent: 20, endIndent: 20),
              ],
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _results.isEmpty
                        ? const Center(child: Text('No areas found', style: TextStyle(color: AppColors.textMuted)))
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final area = _results[i];
                              // No pincode line: every area in a city shares one, so it added a
                              // row of identical numbers with nothing to tell them apart. Search
                              // still matches on pincode.
                              return ListTile(
                                leading: const Icon(Icons.location_on_outlined, color: AppColors.primary),
                                title: Text(area.areaName),
                                trailing: area.id == widget.selectedAreaId
                                    ? const Icon(Icons.check, color: AppColors.primary)
                                    : null,
                                onTap: () => Navigator.of(context).pop(AreaScopeChoice(area)),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The most areas one Home section can show at once (the backend's MAX_AREA_IDS).
const kMaxSectionAreas = 20;

/// Several areas for one Home section (BUG-086): tick any number, or "All of [cityName]".
/// Returns the picked areas in the order they were ticked — empty for the whole city — or
/// null when dismissed. [initial] is the section's current pick.
Future<List<SelectedArea>?> showAreaMultiSheet(
  BuildContext context, {
  required int? cityId,
  required String cityName,
  List<SelectedArea> initial = const [],
}) {
  return showModalBottomSheet<List<SelectedArea>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AreaMultiSheet(cityId: cityId, cityName: cityName, initial: initial),
  );
}

class _AreaMultiSheet extends ConsumerStatefulWidget {
  const _AreaMultiSheet({required this.cityId, required this.cityName, required this.initial});
  final int? cityId;
  final String cityName;
  final List<SelectedArea> initial;

  @override
  ConsumerState<_AreaMultiSheet> createState() => _AreaMultiSheetState();
}

class _AreaMultiSheetState extends ConsumerState<_AreaMultiSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<SelectedArea> _results = [];
  bool _loading = true;

  /// Ticked areas by id, in the order they were ticked.
  late final Map<int, SelectedArea> _picked = {for (final a in widget.initial) a.id: a};

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final areas = await ref.read(serviceProfileRepositoryProvider).searchAreas(q: q, cityId: widget.cityId);
      if (mounted) {
        setState(() {
          _results = areas;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(SelectedArea a) => setState(() => _picked.remove(a.id) ?? (_picked[a.id] = a));

  @override
  Widget build(BuildContext context) {
    final full = _picked.length >= kMaxSectionAreas;
    final count = _picked.length;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
                child: Text('Choose areas', style: Theme.of(context).textTheme.titleMedium),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Tick one or more', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: _onQueryChanged,
                          decoration: const InputDecoration(
                            hintText: 'Search area or pincode',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // What's ticked stays in view whatever the search shows; tap one to untick it.
              if (count > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final a in _picked.values)
                        InputChip(
                          label: Text(a.areaName),
                          onDeleted: () => _toggle(a),
                          deleteButtonTooltipMessage: 'Remove ${a.areaName}',
                        ),
                    ],
                  ),
                ),
              if (full)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Text('You can pick up to $kMaxSectionAreas areas',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: count == 0,
                onChanged: (_) => setState(_picked.clear),
                controlAffinity: ListTileControlAffinity.trailing,
                secondary: const Icon(Icons.location_city_outlined, color: AppColors.primary),
                title: Text('All of ${widget.cityName}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const Divider(height: 1, indent: 20, endIndent: 20),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _results.isEmpty
                        ? const Center(child: Text('No areas found', style: TextStyle(color: AppColors.textMuted)))
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final area = _results[i];
                              final ticked = _picked.containsKey(area.id);
                              return CheckboxListTile(
                                value: ticked,
                                onChanged: ticked || !full ? (_) => _toggle(area) : null,
                                controlAffinity: ListTileControlAffinity.trailing,
                                secondary: const Icon(Icons.location_on_outlined, color: AppColors.primary),
                                title: Text(area.areaName),
                              );
                            },
                          ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(List<SelectedArea>.of(_picked.values)),
                  child: Text(count == 0
                      ? 'Show all of ${widget.cityName}'
                      : 'Show ${count == 1 ? '1 area' : '$count areas'}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
