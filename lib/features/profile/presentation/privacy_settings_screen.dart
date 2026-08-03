import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../data/profile_repository.dart';

/// Minimal privacy controls — currently just the Call-button visibility toggle (default off).
class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends ConsumerState<PrivacySettingsScreen> {
  bool? _showCallButton;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await ref.read(profileRepositoryProvider).getShowCallButton();
      if (mounted) setState(() => _showCallButton = value);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _showCallButton = value;
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).setShowCallButton(value);
    } catch (e) {
      setState(() {
        _showCallButton = !value;
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _showCallButton;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Call visibility')),
      body: value == null
          ? (_error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(message: _error!)))
              : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Show call button on my profile',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            SizedBox(height: 4),
                            Text(
                              'When on, residents viewing your profile can tap to call your registered mobile number.',
                              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Switch(value: value, onChanged: _saving ? null : _toggle),
                    ],
                  ),
                ),
                if (_error != null) ...[const SizedBox(height: 16), ErrorBanner(message: _error!)],
              ],
            ),
    );
  }
}
