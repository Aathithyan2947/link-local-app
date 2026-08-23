import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/input_formatters.dart';
import '../../discovery/discovery_repository.dart';
import '../data/business_repository.dart';
import '../data/rate_models.dart';

/// Service-SP charges editor — per session / monthly / hourly rates.
class SpRatesScreen extends ConsumerStatefulWidget {
  const SpRatesScreen({super.key});

  @override
  ConsumerState<SpRatesScreen> createState() => _SpRatesScreenState();
}

const _rateTypes = ['per_session', 'monthly', 'hourly'];

class _SpRatesScreenState extends ConsumerState<SpRatesScreen> {
  final Map<String, TextEditingController> _controllers = {
    for (final t in _rateTypes) t: TextEditingController(),
  };
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rates = await ref.read(businessRepositoryProvider).myRates();
      for (final r in rates) {
        _controllers[r.rateType]?.text = r.amount.toStringAsFixed(0);
      }
    } catch (_) {
      // First-time SP has no rates yet.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final rates = <SpRate>[];
    for (final t in _rateTypes) {
      final v = double.tryParse(_controllers[t]!.text.trim());
      if (v != null && v > 0) rates.add(SpRate(rateType: t, amount: v));
    }
    if (rates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one rate')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(businessRepositoryProvider).setRates(rates);
      if (!mounted) return;
      ref.invalidate(myRatesProvider);
      ref.invalidate(serviceProviderDetailProvider);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Charges saved')));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save charges')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Charges & rates')),
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
                const Text('Set your charges', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 4),
                const Text('Residents pick one of these when booking. Leave a field blank to hide it.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 18),
                ..._rateTypes.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextField(
                        controller: _controllers[t],
                        keyboardType: kDecimalKeyboard,
                        inputFormatters: kDecimalInput,
                        decoration: InputDecoration(
                          labelText: rateTypeLabels[t],
                          prefixText: '₹ ',
                        ),
                      ),
                    )),
              ],
            ),
    );
  }
}
