import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/auth_header.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../reference/reference_models.dart';
import '../../reference/reference_repository.dart';
import '../data/address_repository.dart';

class AddressVerifyScreen extends ConsumerStatefulWidget {
  const AddressVerifyScreen({super.key});

  @override
  ConsumerState<AddressVerifyScreen> createState() => _AddressVerifyScreenState();
}

class _AddressVerifyScreenState extends ConsumerState<AddressVerifyScreen> {
  String _docType = 'utility_bill';
  String? _fileName;
  Uint8List? _fileBytes;
  bool _loading = false;
  String? _error;
  final _descCtrl = TextEditingController();
  final _refCode = TextEditingController();
  ReferralSource? _refSource;

  @override
  void dispose() {
    _descCtrl.dispose();
    _refCode.dispose();
    super.dispose();
  }

  InputDecoration _refDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      );

  /// Lets the user pick the source: camera capture or a file from the device.
  Future<void> _choose(String docType) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add your proof', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            ListTile(
              leading: const _SourceIcon(Icons.photo_camera_outlined),
              title: const Text('Take a photo', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Capture the document with your camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const _SourceIcon(Icons.folder_open_outlined),
              title: const Text('Choose from device', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Pick an image or PDF from your files'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (source == 'camera') {
      await _fromCamera(docType);
    } else if (source == 'file') {
      await _fromFile(docType);
    }
  }

  Future<void> _fromCamera(String docType) async {
    try {
      final XFile? shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (shot == null) return;
      final bytes = await shot.readAsBytes();
      _setFile(docType, shot.name, bytes);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera unavailable: $e');
    }
  }

  Future<void> _fromFile(String docType) async {
    try {
      final result = await FilePicker.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );
      final file = result?.files.single;
      if (file?.bytes == null) return;
      _setFile(docType, file!.name, file.bytes!);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open files: $e');
    }
  }

  void _setFile(String docType, String name, Uint8List bytes) {
    setState(() {
      _docType = docType;
      _fileName = name;
      _fileBytes = bytes;
      _error = null;
    });
  }

  void _continueAfterAddress() {
    // Next: choose Resident vs Service Provider (per PRD).
    context.go(Routes.roleSelection);
  }

  Future<void> _submit() async {
    final hasReferral = _refSource != null || _refCode.text.trim().isNotEmpty;
    if (_fileBytes == null && !hasReferral) {
      setState(() => _error = 'Add a proof or a referral, or skip for now');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_fileBytes != null) {
        await ref.read(addressRepositoryProvider).uploadProof(
              bytes: _fileBytes!,
              filename: _fileName!,
              docType: _docType,
              description: _docType == 'other' ? _descCtrl.text : null,
            );
      }
      if (hasReferral) {
        await ref.read(addressRepositoryProvider).setReferral(
              referralCode: _refCode.text.trim().isEmpty ? null : _refCode.text.trim(),
              referralSourceId: _refSource?.id,
            );
      }
      _continueAfterAddress();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(referralSourcesProvider).asData?.value ?? const <ReferralSource>[];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const AuthHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthHeading(
                    title: 'Verify your Address',
                    highlight: 'your Address',
                    subtitle: 'This keeps our community authentic and safe',
                  ),
                  const SizedBox(height: 28),
                  const Center(
                    child: Text('Upload your address proof',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 20),
                  _ProofCard(
                    icon: Icons.badge_outlined,
                    title: 'Utility Bills',
                    subtitle: 'Electricity Bill, Water Bill, Landline Bill, Internet Bill, etc.',
                    selected: _fileBytes != null && _docType == 'utility_bill',
                    onTap: () => _choose('utility_bill'),
                  ),
                  const SizedBox(height: 16),
                  _ProofCard(
                    icon: Icons.badge_outlined,
                    title: 'Any Other Proof',
                    subtitle: 'Any other legitimate proof to help us verify your address.',
                    selected: _fileBytes != null && _docType == 'other',
                    onTap: () => _choose('other'),
                  ),
                  if (_fileName != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_fileName!, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ],
                  // For "Other" proofs, let the member name the document so the admin knows
                  // what they're reviewing.
                  if (_docType == 'other' && _fileName != null) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'What is this document?',
                        hintText: 'e.g. Gas connection bill, Society NOC',
                      ),
                    ),
                  ],

                  // ── Referral (moved here from sign-up) ──
                  if (sources.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    DropdownButtonFormField<ReferralSource>(
                      initialValue: _refSource,
                      isExpanded: true,
                      decoration: _refDecoration('How did you hear about us? (optional)'),
                      items: sources.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
                      onChanged: (v) => setState(() => _refSource = v),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Got a referral code?',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 4),
                        const Text('This will help us verify your profile faster',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _refCode,
                          decoration: _refDecoration('Enter Referral code'),
                        ),
                      ],
                    ),
                  ),

                  if (_error != null) ...[const SizedBox(height: 16), ErrorBanner(message: _error!)],
                  const SizedBox(height: 28),
                  PrimaryButton(label: 'Next', loading: _loading, onPressed: _submit),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _loading ? null : _continueAfterAddress,
                      child: const Text('Skip for now',
                          style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofCard extends StatelessWidget {
  const _ProofCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.textSecondary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceIcon extends StatelessWidget {
  const _SourceIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      width: 42,
      decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: AppColors.primary, size: 22),
    );
  }
}
