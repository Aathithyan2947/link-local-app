import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../business/data/availability_models.dart';
import '../../business/data/rate_models.dart';
import '../../discovery/data/sp_detail_models.dart';
import '../../discovery/discovery_repository.dart';
import '../../orders/data/orders_repository.dart';

/// Send a service booking request (free) — the resident picks a rate + a slot.
/// The SP accepts before the resident confirms & pays.
class BookingRequestScreen extends ConsumerStatefulWidget {
  const BookingRequestScreen({super.key, required this.sp});
  final ServiceProviderDetail sp;

  @override
  ConsumerState<BookingRequestScreen> createState() => _BookingRequestScreenState();
}

class _BookingRequestScreenState extends ConsumerState<BookingRequestScreen> {
  SpRate? _rate;
  OpenSlot? _slot;
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (widget.sp.rates.isNotEmpty) _rate = widget.sp.rates.first;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send(bool hasSlots) async {
    final rate = _rate;
    if (rate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please pick a rate')));
      return;
    }
    if (hasSlots && _slot == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please pick a time slot')));
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(ordersRepositoryProvider).placeBooking({
        'spProfileId': widget.sp.id,
        'rateType': rate.rateType,
        if (_slot != null) 'scheduledSlot': _slot!.toJson(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      if (!mounted) return;
      ref.invalidate(spSlotsProvider(widget.sp.id));
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: AppColors.primary, size: 40),
          title: const Text('Request sent'),
          content: Text(
              '${widget.sp.name} will review your request. You’ll get a notification to confirm & pay once it’s accepted.'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 409) {
        setState(() => _slot = null);
        ref.invalidate(spSlotsProvider(widget.sp.id));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That slot was just taken. Pick another.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send request')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send request')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slotsAsync = ref.watch(spSlotsProvider(widget.sp.id));
    final hasSlots = slotsAsync.asData?.value.isNotEmpty ?? false;
    final noRates = widget.sp.rates.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Book ${widget.sp.name}')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: (_sending || noRates) ? null : () => _send(hasSlots),
            child: _sending
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(_rate == null ? 'Send request' : 'Send request  ·  ₹${_rate!.amount.toStringAsFixed(0)}'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (noRates)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: const [
                Icon(Icons.info_outline, color: AppColors.textMuted),
                SizedBox(width: 12),
                Expanded(child: Text('This provider hasn’t published their charges yet. Message them to enquire.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5))),
              ]),
            ),
          if (!noRates) ...[
          const Text('Choose a rate', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          ...widget.sp.rates.map((r) {
            final on = _rate?.rateType == r.rateType;
            return InkWell(
              onTap: () => setState(() => _rate = r),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: on ? AppColors.primarySurface : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: on ? AppColors.primary : AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: on ? AppColors.primary : AppColors.textMuted, size: 22),
                    const SizedBox(width: 12),
                    Expanded(child: Text(r.typeLabel, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('₹${r.amount.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          const Text('Pick a slot', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          slotsAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
            error: (_, _) => const Text('Could not load slots', style: TextStyle(color: AppColors.textMuted)),
            data: (slots) {
              if (slots.isEmpty) {
                return const Text('No published slots — the provider will propose a time after accepting.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13));
              }
              final byDay = <String, List<OpenSlot>>{};
              for (final s in slots) {
                byDay.putIfAbsent(s.dayLabel, () => []).add(s);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: byDay.entries.map((e) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: e.value.map((s) {
                          final on = _slot?.date == s.date && _slot?.startTime == s.startTime;
                          return GestureDetector(
                            onTap: () => setState(() => _slot = s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                color: on ? AppColors.primarySurface : AppColors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: on ? AppColors.primary : AppColors.border),
                              ),
                              child: Text(s.timeLabel,
                                  style: TextStyle(
                                      color: on ? AppColors.primary : AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text('Note (optional)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'What do you need help with?'),
          ),
          ],
        ],
      ),
    );
  }
}
