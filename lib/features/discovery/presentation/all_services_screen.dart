import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/push_guard.dart';
import '../../../core/text/plural.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/data/home_repository.dart';
import '../../home/presentation/widgets/service_icons.dart';
import '../data/service_catalog_models.dart';
import '../discovery_repository.dart';
import 'discover_screen.dart';

/// Every service as a tile, by category, with how many providers offer it where the member is
/// looking (the app-wide location). Home's "Explore More" opens it (BUG-087). A tile opens the
/// Service Providers list limited to that service; back here picks another.
class AllServicesScreen extends ConsumerStatefulWidget {
  const AllServicesScreen({super.key});

  @override
  ConsumerState<AllServicesScreen> createState() => _AllServicesScreenState();
}

class _AllServicesScreenState extends ConsumerState<AllServicesScreen> {
  String _query = '';

  /// The categories whose name, or any of whose services, match the search.
  List<ServiceCatalogCategory> _filter(List<ServiceCatalogCategory> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return [
      for (final c in all)
        if (c.name.toLowerCase().contains(q))
          c
        else if (c.services.where((s) => s.name.toLowerCase().contains(q)).toList() case final matches
            when matches.isNotEmpty)
          ServiceCatalogCategory(id: c.id, name: c.name, services: matches),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(serviceCatalogProvider);
    final place = locationLabel(ref.watch(homeScopeProvider), ref.watch(homeFeedProvider).asData?.value);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('All Services'),
            Text('in $place', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search services',
                prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
              ),
            ),
          ),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Couldn't load services"),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: () => ref.invalidate(serviceCatalogProvider), child: const Text('Retry')),
                  ],
                ),
              ),
              data: (all) {
                final categories = _filter(all);
                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => ref.refresh(serviceCatalogProvider.future),
                  child: categories.isEmpty
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('No services match your search.',
                                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                          ),
                        ])
                      : ListView(
                          padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
                          children: [
                            for (final c in categories) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                                child: Text(c.name.toUpperCase(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        letterSpacing: 0.6,
                                        color: AppColors.textSecondary)),
                              ),
                              GridView.count(
                                crossAxisCount: 3,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.92,
                                children: [for (final s in c.services) _ServiceTile(service: s)],
                              ),
                            ],
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service});
  final CatalogService service;

  @override
  Widget build(BuildContext context) {
    final none = service.count == 0;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.pushPage(MaterialPageRoute(builder: (_) => DiscoverScreen(service: service))),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ServiceIcon(
                    serviceName: service.name, size: 30, color: none ? AppColors.textMuted : AppColors.textPrimary),
                const SizedBox(height: 8),
                Text(service.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(none ? 'None yet' : countLabel(service.count, 'provider'),
                    style: TextStyle(
                        fontSize: 11, color: none ? AppColors.textMuted : AppColors.primary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
