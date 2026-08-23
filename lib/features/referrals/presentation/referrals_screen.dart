import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../feed/data/post_models.dart' show relativeTime;
import '../../home/presentation/widgets/home_widgets.dart';
import '../data/referral_models.dart';
import '../data/referrals_repository.dart';

String _inviteMessage(String code) =>
    "Join me on LinkLocal — your neighbourhood's app for local services, events and groups! "
    'Use my invite code $code when you sign up.';

/// Digits-only, prefixed with the India country code if a bare 10-digit
/// number was entered — what WhatsApp's wa.me deep link expects.
String _waNumber(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.length == 10 ? '91$digits' : digits;
}

class ReferralsScreen extends ConsumerWidget {
  const ReferralsScreen({super.key});

  Future<void> _openInviteSheet(BuildContext context, WidgetRef ref, String code) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InviteSheet(code: code),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(referralsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Invite & Earn Together'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: OutlinedButton(onPressed: () => ref.invalidate(referralsProvider), child: const Text('Retry'))),
        data: (s) => RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => ref.refresh(referralsProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: _StatTile(label: 'People Invited', value: '${s.invitedCount}')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatTile(label: 'Registered', value: '${s.registeredCount}')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatTile(label: 'Points Earned', value: '${s.pointsBalance}')),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Daily referral limit', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text('${s.dailySent}/${s.dailyLimit} Used today', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: s.dailyLimit == 0 ? 0 : (s.dailySent / s.dailyLimit).clamp(0, 1),
                        minHeight: 8,
                        backgroundColor: AppColors.field,
                        valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your Invite Code', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    Text(s.inviteCode, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openInviteSheet(context, ref, s.inviteCode),
                            icon: const Icon(Icons.share_outlined, color: Colors.white, size: 18),
                            label: const Text('Share', style: TextStyle(color: Colors.white)),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: s.inviteCode));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite code copied')));
                            },
                            icon: const Icon(Icons.copy_outlined, color: Colors.white, size: 18),
                            label: const Text('Copy', style: TextStyle(color: Colors.white)),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text('People you referred', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
              const SizedBox(height: 10),
              if (s.referred.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No invites sent yet.')),
              for (final p in s.referred) ...[_ReferredTile(person: p), const SizedBox(height: 10)],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.primary)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ReferredTile extends StatelessWidget {
  const _ReferredTile({required this.person});
  final ReferredPerson person;

  @override
  Widget build(BuildContext context) {
    final registered = person.isRegistered;
    final subtitle = registered
        ? 'Joined via your invite · ${relativeTime(person.registeredAt)}'
        : 'Invite sent · ${relativeTime(person.createdAt)}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Avatar(name: person.name, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(person.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: registered ? AppColors.success.withValues(alpha: 0.12) : AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              registered ? 'Registered' : 'Pending',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: registered ? AppColors.success : AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.code});
  final String code;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendViaWhatsApp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(referralsRepositoryProvider).sendInvite(
            name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
            phone: phone,
            channel: 'whatsapp',
          );
      ref.invalidate(referralsProvider);
      final text = Uri.encodeComponent(_inviteMessage(widget.code));
      await launchUrl(Uri.parse('https://wa.me/${_waNumber(phone)}?text=$text'), mode: LaunchMode.externalApplication);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${e is Exception ? "Couldn't send invite" : e}')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _shareGenerically() async {
    Navigator.of(context).pop();
    await SharePlus.instance.share(ShareParams(text: _inviteMessage(widget.code)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Invite a friend', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 4),
            const Text("Add their number to send via WhatsApp and track when they join.",
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name (optional)')),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile number'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _sending ? null : _sendViaWhatsApp,
              child: _sending
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Send via WhatsApp'),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(onPressed: _sending ? null : _shareGenerically, child: const Text('Share another way')),
            ),
          ],
        ),
      ),
    );
  }
}
