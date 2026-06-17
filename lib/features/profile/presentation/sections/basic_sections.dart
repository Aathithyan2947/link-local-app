import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../auth/application/auth_controller.dart';
import '../../data/profile_repository.dart';
import '../widgets/section_widgets.dart';

const _genders = ['male', 'female', 'do_not_disclose'];

class BasicInfoScreen extends ConsumerStatefulWidget {
  const BasicInfoScreen({super.key});
  @override
  ConsumerState<BasicInfoScreen> createState() => _BasicInfoScreenState();
}

class _BasicInfoScreenState extends ConsumerState<BasicInfoScreen> {
  final _name = TextEditingController();
  final _about = TextEditingController();
  DateTime? _dob;
  String? _gender;
  bool _loading = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final res = await FilePicker.pickFiles(withData: true, type: FileType.image);
    final file = res?.files.single;
    if (file?.bytes == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(profileRepositoryProvider).uploadPhoto(file!.bytes!, file.name);
      ref.invalidate(myProfileProvider);
      await ref.read(authControllerProvider.notifier).refreshUser();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo updated')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await ref.read(profileRepositoryProvider).updateBasic({
        if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
        if (_dob != null) 'dateOfBirth': DateFormat('yyyy-MM-dd').format(_dob!),
        if (_gender != null) 'gender': _gender,
        'aboutMe': _about.text.trim(),
      });
      ref.invalidate(myProfileProvider);
      await ref.read(authControllerProvider.notifier).refreshUser();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myProfileProvider);
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      data: (p) {
        if (!_loaded) {
          _name.text = p.name;
          _about.text = p.aboutMe ?? '';
          _dob = p.dateOfBirth != null ? DateTime.tryParse(p.dateOfBirth!) : null;
          _gender = p.gender;
          _loaded = true;
        }
        return SectionScaffold(
          title: 'Basic Info',
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: AppColors.primarySurface,
                      backgroundImage: p.photoUrl != null
                          ? NetworkImage(AppConfig.assetUrl(p.photoUrl!))
                          : null,
                      child: p.photoUrl == null
                          ? Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 32, color: AppColors.primary, fontWeight: FontWeight.bold))
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _loading ? null : _pickPhoto,
                        child: const CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primary,
                          child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              AppTextField(controller: _name, label: 'Full name'),
              const SizedBox(height: 16),
              Text('Date of birth', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dob ?? DateTime(2000),
                    firstDate: DateTime(1920),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _dob = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.field,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 12),
                      Text(_dob != null ? DateFormat('dd MMM yyyy').format(_dob!) : 'Select date',
                          style: TextStyle(color: _dob != null ? AppColors.textPrimary : AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Gender', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(hintText: 'Select'),
                items: _genders
                    .map((g) => DropdownMenuItem(value: g, child: Text(g.replaceAll('_', ' '))))
                    .toList(),
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: 16),
              AppTextField(controller: _about, label: 'About me', maxLines: 4, hint: 'Tell your neighbours about yourself'),
              const SizedBox(height: 28),
              PrimaryButton(label: 'Save', loading: _loading, onPressed: _save),
            ],
          ),
        );
      },
    );
  }
}

class OfferHelpScreen extends ConsumerStatefulWidget {
  const OfferHelpScreen({super.key});
  @override
  ConsumerState<OfferHelpScreen> createState() => _OfferHelpScreenState();
}

class _OfferHelpScreenState extends ConsumerState<OfferHelpScreen> {
  final _text = TextEditingController();
  bool _loading = false;
  bool _suggesting = false;
  bool _loaded = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    setState(() => _suggesting = true);
    try {
      final s = await ref.read(profileRepositoryProvider).suggestOfferHelp();
      setState(() => _text.text = s);
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await ref.read(profileRepositoryProvider).updateBasic({'canOfferHelpWith': _text.text.trim()});
      ref.invalidate(myProfileProvider);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myProfileProvider);
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      data: (p) {
        if (!_loaded) {
          _text.text = p.canOfferHelpWith ?? '';
          _loaded = true;
        }
        return SectionScaffold(
          title: 'Can offer help with',
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Let neighbours know how you can help.', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              AppTextField(controller: _text, maxLines: 5, hint: 'e.g. Happy to help with...'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _suggesting ? null : _suggest,
                icon: _suggesting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Suggest with AI'),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Save', loading: _loading, onPressed: _save),
            ],
          ),
        );
      },
    );
  }
}
