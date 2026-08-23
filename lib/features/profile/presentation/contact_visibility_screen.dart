import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../data/profile_repository.dart';

const _contactVisibilityOptions = [
  ('all', 'All Users'),
  ('area', 'Only from my Area'),
  ('apartment', 'Only from my Apartment'),
  ('only_me', 'Only Me'),
  ('has_ordered', 'Only who have placed order'),
];

/// Who can view this member's phone/email — matches the "Contact Details Visibility" mockup.
class ContactVisibilityScreen extends ConsumerStatefulWidget {
  const ContactVisibilityScreen({super.key});

  @override
  ConsumerState<ContactVisibilityScreen> createState() => _ContactVisibilityScreenState();
}

class _ContactVisibilityScreenState extends ConsumerState<ContactVisibilityScreen> {
  String? _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await ref.read(profileRepositoryProvider).getVisibilitySettings();
      if (mounted) setState(() => _selected = v['contactVisibility'] ?? 'only_me');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _confirm() async {
    if (_selected == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).setVisibilitySettings(contactVisibility: _selected);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Contact Details Visibility'),
      ),
      body: _selected == null
          ? (_error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(message: _error!)))
              : const Center(child: CircularProgressIndicator(color: AppColors.primary)))
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Allow to View Contact Details',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                          const SizedBox(height: 8),
                          const Text(
                            "*Blocked users will never be able to view profile even if they're from your area",
                            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              children: [
                                for (final (value, label) in _contactVisibilityOptions)
                                  RadioListTile<String>(
                                    value: value,
                                    groupValue: _selected,
                                    activeColor: AppColors.primary,
                                    title: Text(label, style: const TextStyle(fontSize: 14.5)),
                                    onChanged: _saving ? null : (v) => setState(() => _selected = v),
                                  ),
                              ],
                            ),
                          ),
                          if (_error != null) ...[const SizedBox(height: 16), ErrorBanner(message: _error!)],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _confirm,
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        child: _saving
                            ? const SizedBox(
                                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Confirm'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
