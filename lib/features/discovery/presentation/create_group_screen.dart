import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/media/image_editor.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/input_formatters.dart';
import '../data/group_detail_models.dart';
import '../discovery_repository.dart';
import 'group_profile_screen.dart';

/// Form to start a new interest group, or edit one you own when [group] is passed. Create
/// uploads an optional cover image via /media then POSTs to /groups and opens the created
/// group; edit PATCHes the existing group and pops back.
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key, this.group});
  final GroupDetail? group;
  bool get isEdit => group != null;

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
  String? _existingPhotoUrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    if (g == null) return;
    _title.text = g.title;
    _description.text = g.description ?? '';
    _price.text = g.price != null ? g.price!.toStringAsFixed(0) : '';
    _maxMembers.text = g.maxMembers?.toString() ?? '';
    _isPrivate = g.isPrivate;
    _isPaid = g.isPaid;
    _adminApproval = g.adminApprovalNeeded;
    _existingPhotoUrl = g.photoUrl;
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _price, _maxMembers]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    if (!mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final edited = await editPickedImageBytes(context, bytes);
    if (edited == null) return;
    final path = await writeEditedImageToTempFile(edited);
    setState(() => _image = XFile(path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final repo = ref.read(discoveryRepositoryProvider);
      String? photoUrl;
      if (_image != null) photoUrl = await repo.uploadImage(_image!.path, type: 'group');

      final data = {
        'title': _title.text.trim(),
        if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
        'photoUrl': ?photoUrl,
        'isPrivate': _isPrivate,
        'isPaid': _isPaid,
        if (_isPaid && _price.text.trim().isNotEmpty) 'price': double.tryParse(_price.text.trim()),
        if (_maxMembers.text.trim().isNotEmpty) 'maxMembers': int.tryParse(_maxMembers.text.trim()),
        'adminApprovalNeeded': _adminApproval,
      };

      if (widget.isEdit) {
        final id = widget.group!.id;
        await repo.updateGroup(id, data);
        if (!mounted) return;
        ref.invalidate(groupsProvider);
        ref.invalidate(myGroupsProvider);
        ref.invalidate(groupDetailProvider(id));
        await ref.read(groupDetailProvider(id).future);
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        final id = await repo.createGroup(data);
        if (!mounted) return;
        ref.invalidate(groupsProvider);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => GroupProfileScreen(id: id)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.isEdit ? 'Could not save group' : 'Could not create group')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit Group' : 'Start a Group')),
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
            _field(_maxMembers, 'Max members (optional)', keyboard: TextInputType.number, formatters: kIntegerInput),
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
            if (_isPaid) _field(_price, 'Price (₹)', keyboard: kDecimalKeyboard, formatters: kDecimalInput),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(widget.isEdit ? 'Save Changes' : 'Create Group'),
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
            image: _image != null
                ? DecorationImage(image: FileImage(File(_image!.path)), fit: BoxFit.cover)
                : (_existingPhotoUrl != null
                    ? DecorationImage(image: NetworkImage(AppConfig.assetUrl(_existingPhotoUrl!)), fit: BoxFit.cover)
                    : null),
          ),
          child: (_image != null || _existingPhotoUrl != null)
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

  Widget _field(TextEditingController c, String label, {bool required = false, int maxLines = 1, TextInputType? keyboard, List<TextInputFormatter>? formatters}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
    );
  }
}
