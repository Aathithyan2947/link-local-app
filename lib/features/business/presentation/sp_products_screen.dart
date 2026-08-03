import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../services/presentation/category_fields_form_screen.dart';
import '../data/business_repository.dart';
import '../data/product_models.dart';
import 'add_product_screen.dart';

/// The SP's product manager — the "Your Items" frame. Edit / delete / add. When
/// [fromOnboarding], this is a step in a menu-type SP's "Complete your profile" chain, so an
/// extra "Save & Proceed" button continues on to whatever's left in [nextCategories].
class SpProductsScreen extends ConsumerWidget {
  const SpProductsScreen({super.key, this.fromOnboarding = false, this.nextCategories = const []});
  final bool fromOnboarding;
  final List<String> nextCategories;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddProductScreen()));
    ref.invalidate(myProductsProvider);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, SpProduct p) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddProductScreen(product: p)));
    ref.invalidate(myProductsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, SpProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove "${p.name}" from your menu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(businessRepositoryProvider).deleteProduct(p.id);
      ref.invalidate(myProductsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProductsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Your Items')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: fromOnboarding
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(onPressed: () => _add(context, ref), child: const Text('+ Add Item(s)')),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () => pushOnboardingStep(context, ref, nextCategories, replace: true),
                      child: const Text('Save & Proceed'),
                    ),
                  ],
                )
              : ElevatedButton(
                  onPressed: () => _add(context, ref),
                  child: const Text('+ Add Item(s)'),
                ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: OutlinedButton(onPressed: () => ref.invalidate(myProductsProvider), child: const Text('Retry')),
        ),
        data: (products) {
          if (products.isEmpty) {
            return const Center(child: Text('No items yet — add your first product.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final p = products[i];
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    _thumb(p),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          if (p.price != null) ...[
                            const SizedBox(height: 2),
                            Text('₹ ${p.price!.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                          ],
                          if (p.quantityLabel.isNotEmpty)
                            Text(p.quantityLabel, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    _iconBtn(Icons.edit_square, AppColors.primary, () => _edit(context, ref, p)),
                    const SizedBox(width: 8),
                    _iconBtn(Icons.delete_outline, AppColors.error, () => _delete(context, ref, p)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _thumb(SpProduct p) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: (p.photoUrl != null && p.photoUrl!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: AppConfig.assetUrl(p.photoUrl!),
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _placeholder(),
              )
            : _placeholder(),
      );

  Widget _placeholder() => Container(
        width: 64,
        height: 64,
        color: AppColors.primarySurface,
        child: const Icon(Icons.bakery_dining_outlined, color: AppColors.primary),
      );

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) => Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, color: color, size: 22)),
        ),
      );
}
