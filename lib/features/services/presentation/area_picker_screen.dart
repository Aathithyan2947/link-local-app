import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../data/service_profile_repository.dart';

/// Full-screen searchable multi-select picker for the 'pincode' field type — the SP finds
/// serviceable areas by pincode or area name (the backend search unions both) and picks any
/// number of them. Returns the updated selection via `Navigator.pop`.
class AreaPickerScreen extends ConsumerStatefulWidget {
  const AreaPickerScreen({super.key, required this.initialSelection, this.cityId});

  final List<SelectedArea> initialSelection;
  final int? cityId;

  @override
  ConsumerState<AreaPickerScreen> createState() => _AreaPickerScreenState();
}

class _AreaPickerScreenState extends ConsumerState<AreaPickerScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<SelectedArea> _results = [];
  late final Map<int, SelectedArea> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {for (final a in widget.initialSelection) a.id: a};
    _runSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results =
          await ref.read(serviceProfileRepositoryProvider).searchAreas(q: q, cityId: widget.cityId);
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(SelectedArea a) {
    setState(() {
      if (_selected.containsKey(a.id)) {
        _selected.remove(a.id);
      } else {
        _selected[a.id] = a;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Select service areas'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _selected.values.toList()),
            child: Text('Done (${_selected.length})'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: 'Search by area name or pincode',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ErrorBanner(message: _error!)),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selected.values
                    .map((a) => Chip(
                          label: Text(a.label),
                          onDeleted: () => _toggle(a),
                        ))
                    .toList(),
              ),
            ),
          Expanded(
            child: _results.isEmpty && !_loading
                ? const Center(
                    child: Text('No areas found', style: TextStyle(color: AppColors.textMuted)))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final a = _results[i];
                      final checked = _selected.containsKey(a.id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (_) => _toggle(a),
                        title: Text(a.label),
                        subtitle: a.cityName != null ? Text(a.cityName!) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
