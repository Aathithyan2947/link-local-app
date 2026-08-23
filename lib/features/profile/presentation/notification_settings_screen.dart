import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../data/profile_repository.dart';

/// Notification/alert toggle preferences — distinct from [NotificationsScreen], which is the
/// notification inbox. Matches the "Notifications & Alerts" settings mockup.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  Map<String, bool>? _prefs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await ref.read(profileRepositoryProvider).getNotificationPrefs();
      if (mounted) setState(() => _prefs = v);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _toggle(String key, bool value) async {
    final prev = _prefs!;
    setState(() => _prefs = {...prev, key: value});
    try {
      await ref.read(profileRepositoryProvider).setNotificationPrefs({key: value});
    } catch (e) {
      setState(() {
        _prefs = prev;
        _error = e.toString();
      });
    }
  }

  Widget _switchTile(String key, String label) {
    return SwitchListTile(
      value: _prefs![key] ?? true,
      activeColor: AppColors.primary,
      title: Text(label, style: const TextStyle(fontSize: 14.5)),
      onChanged: (v) => _toggle(key, v),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Notifications & Alerts'),
      ),
      body: _prefs == null
          ? (_error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(message: _error!)))
              : const Center(child: CircularProgressIndicator(color: AppColors.primary)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('Notifications', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(children: [
                    _switchTile('notifyApp', 'App Notifications'),
                    _switchTile('notifyWhatsapp', 'Whatsapp Notifications'),
                    _switchTile('notifyEmail', 'Email Notifications'),
                  ]),
                ),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('Alerts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(children: [
                    _switchTile('alertMessages', 'Messages'),
                    _switchTile('alertOrders', 'Orders'),
                    _switchTile('alertPayments', 'Payments'),
                  ]),
                ),
                if (_error != null) ...[const SizedBox(height: 16), ErrorBanner(message: _error!)],
              ],
            ),
    );
  }
}
