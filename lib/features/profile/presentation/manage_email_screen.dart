import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../data/profile_repository.dart';

/// "Your Email" — Manage your Email. Matches the mockup: registered address + Change/Remove,
/// or an Add button when none is set.
class ManageEmailScreen extends ConsumerStatefulWidget {
  const ManageEmailScreen({super.key});

  @override
  ConsumerState<ManageEmailScreen> createState() => _ManageEmailScreenState();
}

class _ManageEmailScreenState extends ConsumerState<ManageEmailScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _addOrChange(String? current) async {
    final value = await _promptEmail(context, current);
    if (value == null || value.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateEmail(value);
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
        title: const Text('Remove email?'),
        content: const Text('You will no longer be able to sign in with this email address.'),
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
      await ref.read(profileRepositoryProvider).updateEmail(null);
      ref.invalidate(myProfileProvider);
      await ref.read(myProfileProvider.future);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Future<String?> _promptEmail(BuildContext context, String? current) {
    final controller = TextEditingController(text: current ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Email address'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'you@example.com'),
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
        title: const Text('Your Email'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(message: e.toString()))),
        data: (p) {
          final email = p.email;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Manage your Email', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 20),
                const Text('Registered Email Address:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                const SizedBox(height: 10),
                if (email != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: Text(email, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary))),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            onPressed: _busy ? null : () => _addOrChange(email),
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
