import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../business/data/product_models.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../../messages/presentation/chat_screen.dart';
import '../../orders/data/cart.dart';
import '../../orders/presentation/product_details_screen.dart';
import '../data/sp_detail_models.dart';
import '../discovery_repository.dart';
import 'service_provider_detail_screen.dart' show CartBar;
import 'widgets/discover_cards.dart';

String? _customFieldValue(ServiceProviderDetail sp, String category, String fieldName) {
  for (final f in sp.customFields) {
    if (f.category == category && f.fieldName.trim().toLowerCase() == fieldName.toLowerCase()) {
      final v = f.value?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
  }
  return null;
}

/// Full item listing for a menu-type SP — reached via the profile's "Order" button or the
/// Item List section's "Show All" link. Matches the Figma "Listing (buyer)" frame.
class SpMenuListingScreen extends ConsumerWidget {
  const SpMenuListingScreen({super.key, required this.spId});
  final int spId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(serviceProviderDetailProvider(spId));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: OutlinedButton(
            onPressed: () => ref.invalidate(serviceProviderDetailProvider(spId)),
            child: const Text('Retry'),
          ),
        ),
        data: (sp) {
          final timing = _customFieldValue(sp, 'delivery', 'Order placement timing');
          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  _Header(sp: sp),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (timing != null) _TimingBanner(category: sp.service, timing: timing),
                        if (timing != null) const SizedBox(height: 14),
                        const Text('For any inquiry, Contact here',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(height: 10),
                        _ContactIcons(sp: sp),
                        const SizedBox(height: 18),
                        ...sp.products.map((p) => _ListingItem(product: p, spId: sp.id, spName: sp.name)),
                      ],
                    ),
                  ),
                ],
              ),
              CartBar(spId: sp.id),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.sp});
  final ServiceProviderDetail sp;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          height: topPad + 110,
          decoration: const BoxDecoration(color: AppColors.primary),
          padding: EdgeInsets.only(top: topPad + 8, left: 8),
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        Positioned(
          top: topPad + 8,
          right: 20,
          child: RatingBadge(value: sp.ratingAvg),
        ),
        SizedBox(
          width: double.infinity,
          child: Padding(
            padding: EdgeInsets.only(top: topPad + 75),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Avatar(name: sp.name, photoUrl: sp.photoUrl, radius: 40),
                ),
                const SizedBox(height: 10),
                Text(sp.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
                if (sp.service != null) ...[
                  const SizedBox(height: 2),
                  Text(sp.service!, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13.5)),
                ],
                if (sp.locationLabel != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 3),
                    Text(sp.locationLabel!, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  ]),
                ],
              ],
            ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimingBanner extends StatelessWidget {
  const _TimingBanner({required this.category, required this.timing});
  final String? category;
  final String timing;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            const Icon(Icons.schedule, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                  children: [
                    TextSpan(text: 'This ${category ?? 'seller'} only takes orders '),
                    TextSpan(text: timing, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _ContactIcons extends StatelessWidget {
  const _ContactIcons({required this.sp});
  final ServiceProviderDetail sp;

  @override
  Widget build(BuildContext context) {
    if (sp.userId == null) return const SizedBox.shrink();
    final showCall = sp.showCallButton && (sp.mobile?.isNotEmpty ?? false);
    return Row(
      children: [
        _iconBtn(
          icon: Icons.chat_bubble_outline,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatScreen(
              otherUserId: sp.userId!,
              otherName: sp.name,
              otherPhoto: sp.photoUrl,
              messageType: 'direct',
              entityType: 'sp_profile',
              entityId: sp.id,
            ),
          )),
        ),
        if (showCall) ...[
          const SizedBox(width: 10),
          _iconBtn(icon: Icons.call_outlined, onTap: () {}),
        ],
      ],
    );
  }

  Widget _iconBtn({required IconData icon, required VoidCallback onTap}) => Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: Colors.white, size: 20)),
        ),
      );
}

class _ListingItem extends ConsumerWidget {
  const _ListingItem({required this.product, required this.spId, required this.spName});
  final SpProduct product;
  final int spId;
  final String spName;

  bool get _hasCustomization => product.customizationNotes?.trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final qty = cart.spProfileId == spId ? (cart.lines[product.id]?.qty ?? 0) : 0;

    void openDetails() => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProductDetailsScreen(product: product, spId: spId, spName: spName),
        ));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _hasCustomization ? openDetails : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: (product.photoUrl != null && product.photoUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: AppConfig.assetUrl(product.photoUrl!),
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _ph(),
                      )
                    : _ph(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    if (product.price != null)
                      Text('₹${product.price!.toStringAsFixed(0)}${product.quantityLabel.isNotEmpty ? '  |  ${product.quantityLabel}' : ''}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    if (_hasCustomization) ...[
                      const SizedBox(height: 2),
                      const Text('Custom options available',
                          style: TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              if (qty == 0)
                OutlinedButton(
                  onPressed: _hasCustomization ? openDetails : () => notifier.add(spId, spName, product),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size(70, 34),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Add'),
                )
              else
                _stepper(qty, () => notifier.setQty(product.id, qty - 1), () => notifier.add(spId, spName, product)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepper(int qty, VoidCallback minus, VoidCallback plus) => Container(
        decoration: BoxDecoration(border: Border.all(color: AppColors.primary), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            InkWell(onTap: minus, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.remove, size: 16, color: AppColors.primary))),
            SizedBox(width: 22, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
            InkWell(onTap: plus, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.add, size: 16, color: AppColors.primary))),
          ],
        ),
      );

  Widget _ph() => Container(
        width: 60,
        height: 60,
        color: AppColors.primarySurface,
        child: const Icon(Icons.bakery_dining_outlined, color: AppColors.primary),
      );
}
