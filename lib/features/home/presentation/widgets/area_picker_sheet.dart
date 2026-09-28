import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../services/data/service_profile_repository.dart';

/// Bottom sheet letting the resident pick a different area within their own city — re-scopes
/// the Home feed to that area (see `homeScopeProvider.setArea`). Single-select; distinct from
/// the full-screen multi-select `AreaPickerScreen` used for SP service-area configuration.
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
