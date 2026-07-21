import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/business_repository.dart';

/// SP blackout / off dates that override the weekly availability (holidays etc.).
class BlackoutDatesScreen extends ConsumerWidget {
  const BlackoutDatesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final ymd = '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    try {
      await ref.read(businessRepositoryProvider).addBlackout(ymd, reason: 'holiday');
      ref.invalidate(myAvailabilityProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add date')));
      }
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, int id) async {
    try {
      await ref.read(businessRepositoryProvider).deleteBlackout(id);
      ref.invalidate(myAvailabilityProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove date')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(myAvailabilityProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Off days')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add date'),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load off days')),
        data: (d) {
          final blackouts = d.blackouts;
          if (blackouts.isEmpty) {
            return const _Empty();
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: blackouts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final b = blackouts[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_busy_outlined, color: AppColors.warning),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          if (b.reason != null) Text(b.reason!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () => _remove(context, ref, b.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.beach_access_outlined, size: 48, color: AppColors.textMuted),
              SizedBox(height: 12),
              Text('No off days yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              SizedBox(height: 6),
              Text('Add dates you’re unavailable — they’ll be hidden from your bookable slots.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
}
