import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/business_repository.dart';

/// SP delivery preferences — the "Delivery settings" card on the dashboard.
/// Backed by PUT /profiles/me/delivery.
class DeliverySettingsScreen extends ConsumerStatefulWidget {
  const DeliverySettingsScreen({super.key});

  @override
  ConsumerState<DeliverySettingsScreen> createState() => _DeliverySettingsScreenState();
}

class _DeliverySettingsScreenState extends ConsumerState<DeliverySettingsScreen> {
  final _radius = TextEditingController();
  final _charge = TextEditingController();
  final _minOrder = TextEditingController();
  final _time = TextEditingController();
  final _notes = TextEditingController();
  final _packaging = TextEditingController();
  final _freeThreshold = TextEditingController();
  final _leadTime = TextEditingController();
  final _advancePct = TextEditingController();
  bool _homeDelivery = false;
  bool _pickup = true;
  bool _advanceEnabled = false;
  String _advanceType = 'full_advance'; // full_advance | partial_advance
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (d, pt) = await ref.read(businessRepositoryProvider).mySettings();
      if (d != null) {
        _homeDelivery = (d['offersHomeDelivery'] as bool?) ?? false;
        _pickup = (d['offersPickup'] as bool?) ?? true;
        _radius.text = _num(d['deliveryRadiusKm']);
        _charge.text = _num(d['deliveryCharge']);
        _minOrder.text = _num(d['minOrderAmount']);
        _time.text = _num(d['deliveryTimeMinutes']);
        _notes.text = (d['deliveryNotes'] as String?) ?? '';
        _packaging.text = _num(d['packagingCharge']);
        _freeThreshold.text = _num(d['freeDeliveryThreshold']);
        _leadTime.text = _num(d['orderLeadTimeHours']);
      }
      if (pt != null) {
        final terms = pt['paymentTerms'] as String?;
        _advanceEnabled = terms == 'full_advance' || terms == 'partial_advance';
        _advanceType = terms == 'partial_advance' ? 'partial_advance' : 'full_advance';
        _advancePct.text = _num(pt['partialAdvancePct']);
      }
    } catch (_) {
      // First-time SPs have no rows yet — defaults are fine.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _num(dynamic v) => v == null ? '' : '${(v is num) ? (v % 1 == 0 ? v.toInt() : v) : v}';

  @override
  void dispose() {
    for (final c in [_radius, _charge, _minOrder, _time, _notes, _packaging, _freeThreshold, _leadTime, _advancePct]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(businessRepositoryProvider);
      double? d(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());
      int? i(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
      await repo.setDelivery({
        'offersHomeDelivery': _homeDelivery,
        'offersPickup': _pickup,
        if (d(_radius) != null) 'deliveryRadiusKm': d(_radius),
        if (d(_charge) != null) 'deliveryCharge': d(_charge),
        if (d(_minOrder) != null) 'minOrderAmount': d(_minOrder),
        if (i(_time) != null) 'deliveryTimeMinutes': i(_time),
        if (d(_packaging) != null) 'packagingCharge': d(_packaging),
        if (d(_freeThreshold) != null) 'freeDeliveryThreshold': d(_freeThreshold),
        if (i(_leadTime) != null) 'orderLeadTimeHours': i(_leadTime),
        if (_notes.text.trim().isNotEmpty) 'deliveryNotes': _notes.text.trim(),
      });
      await repo.setPaymentTerms({
        'paymentTerms': _advanceEnabled ? _advanceType : 'on_delivery',
        if (_advanceEnabled && _advanceType == 'partial_advance' && d(_advancePct) != null)
          'partialAdvancePct': d(_advancePct),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery settings saved')));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save settings')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Delivery settings')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _saving || _loading ? null : _save,
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save'),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _toggle('Offer home delivery', _homeDelivery, (v) => setState(() => _homeDelivery = v)),
                _toggle('Offer pickup', _pickup, (v) => setState(() => _pickup = v)),
                const SizedBox(height: 8),
                if (_homeDelivery) ...[
                  _field(_radius, 'Delivery radius (km)'),
                  const SizedBox(height: 12),
                  _field(_charge, 'Delivery charge (₹)'),
                  const SizedBox(height: 12),
                  _field(_time, 'Delivery time (minutes)'),
                  const SizedBox(height: 12),
                  _field(_freeThreshold, 'Free delivery above (₹)'),
                  const SizedBox(height: 12),
                ],
                _field(_minOrder, 'Minimum order amount (₹)'),
                const SizedBox(height: 12),
                _field(_packaging, 'Packaging charges (₹)'),
                const SizedBox(height: 12),
                _field(_leadTime, 'Order lead time (hours in advance)'),
                const SizedBox(height: 12),
                _field(_notes, 'Notes for buyers', maxLines: 3),
                const Divider(height: 32),
                const Text('Advanced payment settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                _toggle('Require advance payment', _advanceEnabled, (v) => setState(() => _advanceEnabled = v)),
                if (_advanceEnabled) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(child: _typeChoice('Full advance', 'full_advance')),
                    const SizedBox(width: 10),
                    Expanded(child: _typeChoice('Percentage', 'partial_advance')),
                  ]),
                  if (_advanceType == 'partial_advance') ...[
                    const SizedBox(height: 12),
                    _field(_advancePct, 'Advance percentage (%)'),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _typeChoice(String label, String value) => InkWell(
        onTap: () => setState(() => _advanceType = value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _advanceType == value ? AppColors.primarySurface : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _advanceType == value ? AppColors.primary : AppColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                  color: _advanceType == value ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: FontWeight.w600)),
        ),
      );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AppColors.primary,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        value: value,
        onChanged: onChanged,
      );

  Widget _field(TextEditingController c, String label, {int maxLines = 1}) => TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: maxLines == 1 ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      );
}
