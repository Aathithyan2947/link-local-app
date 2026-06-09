import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/profile_repository.dart';
import '../widgets/section_widgets.dart';

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProfileProvider);
    return SectionScaffold(
      title: 'Products / Menu',
      addLabel: 'Add item',
      onAdd: () async {
        final name = TextEditingController();
        final desc = TextEditingController();
        final price = TextEditingController();
        final unit = TextEditingController();
        await showFormSheet(context,
            title: 'Add Product',
            fields: (_) => [
                  TextField(controller: name, decoration: const InputDecoration(hintText: 'Name')),
                  const SizedBox(height: 12),
                  TextField(controller: desc, decoration: const InputDecoration(hintText: 'Description')),
                  const SizedBox(height: 12),
                  TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Price (₹)')),
                  const SizedBox(height: 12),
                  TextField(controller: unit, decoration: const InputDecoration(hintText: 'Unit (per piece, per kg...)')),
                ],
            onSave: () => ref.read(profileRepositoryProvider).addProduct({
                  'name': name.text.trim(),
                  if (desc.text.trim().isNotEmpty) 'description': desc.text.trim(),
                  if (price.text.trim().isNotEmpty) 'price': double.tryParse(price.text.trim()),
                  if (unit.text.trim().isNotEmpty) 'unit': unit.text.trim(),
                }));
        ref.invalidate(myProfileProvider);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptySection(message: '$e'),
        data: (p) {
          if (p.products.isEmpty) return const EmptySection(message: 'Add products or menu items you offer.');
          return ListView(
            padding: const EdgeInsets.only(top: 16, bottom: 90),
            children: p.products
                .map((it) => ItemTile(
                      title: it.label,
                      subtitle: it.subtitle,
                      icon: Icons.shopping_bag_outlined,
                      onDelete: () async {
                        await ref.read(profileRepositoryProvider).deleteItem('products', it.id);
                        ref.invalidate(myProfileProvider);
                      },
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

const _timing = ['after_24h', 'after_48h', 'after_confirmation'];

class DeliveryScreen extends ConsumerStatefulWidget {
  const DeliveryScreen({super.key});
  @override
  ConsumerState<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends ConsumerState<DeliveryScreen> {
  final _charge = TextEditingController();
  final _minOrder = TextEditingController();
  final _radius = TextEditingController();
  bool _homeDelivery = false;
  bool _pickup = false;
  String _timingType = _timing.first;
  bool _loading = false;

  @override
  void dispose() {
    _charge.dispose();
    _minOrder.dispose();
    _radius.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await ref.read(profileRepositoryProvider).setDelivery({
        'offersHomeDelivery': _homeDelivery,
        'offersPickup': _pickup,
        'deliveryTimingType': _timingType,
        if (_charge.text.trim().isNotEmpty) 'deliveryCharge': double.tryParse(_charge.text.trim()),
        if (_minOrder.text.trim().isNotEmpty) 'minOrderAmount': double.tryParse(_minOrder.text.trim()),
        if (_radius.text.trim().isNotEmpty) 'deliveryRadiusKm': double.tryParse(_radius.text.trim()),
      });
      ref.invalidate(myProfileProvider);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Delivery Preferences',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SwitchListTile(
            value: _homeDelivery,
            onChanged: (v) => setState(() => _homeDelivery = v),
            title: const Text('Offer home delivery'),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _pickup,
            onChanged: (v) => setState(() => _pickup = v),
            title: const Text('Offer pickup'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          AppTextField(controller: _charge, label: 'Delivery charge (₹)', keyboardType: TextInputType.number, hint: '0 = free'),
          const SizedBox(height: 16),
          AppTextField(controller: _minOrder, label: 'Minimum order amount (₹)', keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          AppTextField(controller: _radius, label: 'Delivery radius (km)', keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          Text('Delivery timing', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _timingType,
            items: _timing
                .map((t) => DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' '))))
                .toList(),
            onChanged: (v) => setState(() => _timingType = v ?? _timingType),
          ),
          const SizedBox(height: 28),
          PrimaryButton(label: 'Save', loading: _loading, onPressed: _save),
        ],
      ),
    );
  }
}
