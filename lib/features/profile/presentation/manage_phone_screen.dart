import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../data/profile_repository.dart';

/// "Your Phone Number" — Manage your Phone Number. Matches the mockup: registered number +
/// Change/Remove, or an Add button when none is set.
class ManagePhoneScreen extends ConsumerStatefulWidget {
  const ManagePhoneScreen({super.key});

  @override
  ConsumerState<ManagePhoneScreen> createState() => _ManagePhoneScreenState();
}

class _ManagePhoneScreenState extends ConsumerState<ManagePhoneScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _addOrChange(String? current) async {
    final value = await _promptPhone(context, current);
    if (value == null || value.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updatePhone(value);
      ref.invalidate(myProfileProvider);
      await ref.read(myProfileProvider.future);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove phone number?'),
        content: const Text('You will no longer be able to sign in with this phone number.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updatePhone(null);
      ref.invalidate(myProfileProvider);
      await ref.read(myProfileProvider.future);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Future<String?> _promptPhone(BuildContext context, String? current) {
    final controller = TextEditingController(text: current ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Phone number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(hintText: '98765 43210'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myProfileProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Your Phone Number'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(message: e.toString()))),
        data: (p) {
          final mobile = p.mobile;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Manage your Phone Number', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 20),
                const Text('Registered Phone Number:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                const SizedBox(height: 10),
                if (mobile != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: Text(mobile, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary))),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            onPressed: _busy ? null : () => _addOrChange(mobile),
                            style: ElevatedButton.styleFrom(minimumSize: const Size(100, 38)),
                            child: const Text('Change'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _busy ? null : _remove,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(100, 38),
                              backgroundColor: AppColors.error,
                            ),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  ElevatedButton(
                    onPressed: _busy ? null : () => _addOrChange(null),
                    child: const Text('Add'),
                  ),
                if (_error != null) ...[const SizedBox(height: 16), ErrorBanner(message: _error!)],
              ],
            ),
          );
        },
      ),
    );
  }
}
