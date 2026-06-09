import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_controller.dart';
import '../data/address_models.dart';
import '../data/address_repository.dart';
import 'widgets/proof_picker.dart';

class AddressProofScreen extends ConsumerStatefulWidget {
  const AddressProofScreen({super.key});

  @override
  ConsumerState<AddressProofScreen> createState() => _AddressProofScreenState();
}

class _AddressProofScreenState extends ConsumerState<AddressProofScreen> {
  String _docType = 'utility_bill';
  String? _fileName;
  Uint8List? _fileBytes;
  bool _loading = false;
  String? _error;

  Future<void> _pick(String docType) async {
    final doc = await pickProofDocument(context);
    if (doc != null) {
      setState(() {
        _docType = docType;
        _fileName = doc.name;
        _fileBytes = doc.bytes;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_fileBytes == null) {
      setState(() => _error = 'Please select a proof document');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(addressRepositoryProvider).uploadProof(
            bytes: _fileBytes!,
            filename: _fileName!,
            docType: _docType,
          );
      ref.invalidate(myAddressProofProvider);
      await ref.read(authControllerProvider.notifier).refreshUser();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Address proof submitted for review')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myAddressProofProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Address Proof')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (info) {
          if (!info.hasAddress) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Add your address first, then you can upload its proof here.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _AddressCard(info: info),
              const SizedBox(height: 16),
              _StatusBanner(status: info.status, label: info.statusLabel),
              if (!info.isVerified) ...[
                const SizedBox(height: 24),
                const Text('Upload your address proof',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Electricity, water, internet bill, or any legitimate proof (non-ID).',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                ProofTypeCard(
                  icon: Icons.badge_outlined,
                  title: 'Utility Bills',
                  subtitle: 'Electricity Bill, Water Bill, Landline Bill, Internet Bill, etc.',
                  selected: _fileBytes != null && _docType == 'utility_bill',
                  onTap: () => _pick('utility_bill'),
                ),
                const SizedBox(height: 14),
                ProofTypeCard(
                  icon: Icons.badge_outlined,
                  title: 'Any Other Proof',
                  subtitle: 'Any other legitimate proof to help us verify your address.',
                  selected: _fileBytes != null && _docType == 'other',
                  onTap: () => _pick('other'),
                ),
                if (_fileName != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_fileName!, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[const SizedBox(height: 16), ErrorBanner(message: _error!)],
                const SizedBox(height: 24),
                PrimaryButton(
                  label: info.status == 'rejected' ? 'Re-submit proof' : 'Submit proof',
                  loading: _loading,
                  onPressed: _submit,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.info});
  final AddressProofInfo info;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.home_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.fullAddress ?? 'Your address',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (info.city != null)
                  Text(info.city!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.label});
  final String status;
  final String label;
  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, IconData icon) = switch (status) {
      'approved' => (AppColors.primarySurface, AppColors.primary, Icons.verified_user),
      'pending' => (const Color(0xFFFFF4E5), AppColors.warning, Icons.hourglass_top),
      'rejected' => (const Color(0xFFFDECEC), AppColors.error, Icons.error_outline),
      _ => (AppColors.field, AppColors.textSecondary, Icons.upload_file),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
