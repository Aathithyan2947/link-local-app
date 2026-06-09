import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../discovery/discovery_repository.dart';
import '../widgets/home_widgets.dart';

class ExploreTab extends ConsumerWidget {
  const ExploreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spAsync = ref.watch(serviceProvidersProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Service Providers')),
      body: spAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No service providers nearby yet'));
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(serviceProvidersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final sp = items[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Avatar(name: sp.name, photoUrl: sp.photoUrl, radius: 26),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sp.name, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text(sp.service ?? 'Service Provider',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(minimumSize: const Size(96, 40)),
                        child: const Text('View'),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
