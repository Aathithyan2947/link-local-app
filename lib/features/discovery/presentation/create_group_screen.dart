import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../discovery_repository.dart';
import 'group_profile_screen.dart';

/// Form to start a new interest group. Uploads an optional cover image via
/// /media, then POSTs to /groups and opens the created group.
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _maxMembers = TextEditingController();

  bool _isPrivate = false;
  bool _isPaid = false;
  bool _adminApproval = false;
  XFile? _image;
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in [_title, _description, _price, _maxMembers]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img != null) setState(() => _image = img);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final repo = ref.read(discoveryRepositoryProvider);
      String? photoUrl;
      if (_image != null) photoUrl = await repo.uploadImage(_image!.path);

      final id = await repo.createGroup({
        'title': _title.text.trim(),
        if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
        'photoUrl': ?photoUrl,
        'isPrivate': _isPrivate,
        'isPaid': _isPaid,
        if (_isPaid && _price.text.trim().isNotEmpty) 'price': double.tryParse(_price.text.trim()),
        if (_maxMembers.text.trim().isNotEmpty) 'maxMembers': int.tryParse(_maxMembers.text.trim()),
        'adminApprovalNeeded': _adminApproval,
      });
      if (!mounted) return;
      ref.invalidate(groupsProvider);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GroupProfileScreen(id: id)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create group')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Start a Group')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _imagePicker(),
            const SizedBox(height: 16),
            _field(_title, 'Group name', required: true),
            const SizedBox(height: 12),
            _field(_description, 'Description / guidelines', maxLines: 4),
            const SizedBox(height: 12),
            _field(_maxMembers, 'Max members (optional)', keyboard: TextInputType.number),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: AppColors.primary,
              title: const Text('Private group', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Only invited people can find it', style: TextStyle(fontSize: 12.5)),
              value: _isPrivate,
              onChanged: (v) => setState(() => _isPrivate = v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: AppColors.primary,
              title: const Text('Approve members', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('You review each join request', style: TextStyle(fontSize: 12.5)),
              value: _adminApproval,
              onChanged: (v) => setState(() => _adminApproval = v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: AppColors.primary,
              title: const Text('Paid group', style: TextStyle(fontWeight: FontWeight.w600)),
              value: _isPaid,
              onChanged: (v) => setState(() => _isPaid = v),
            ),
            if (_isPaid) _field(_price, 'Price (₹)', keyboard: TextInputType.number),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Create Group'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePicker() => GestureDetector(
        onTap: _pickImage,
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: AppColors.field,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            image: _image != null ? DecorationImage(image: FileImage(File(_image!.path)), fit: BoxFit.cover) : null,
          ),
          child: _image != null
              ? null
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 34, color: AppColors.textMuted),
                      SizedBox(height: 6),
                      Text('Add a group photo', style: TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                ),
        ),
      );

  Widget _field(TextEditingController c, String label, {bool required = false, int maxLines = 1, TextInputType? keyboard}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
    );
  }
}
