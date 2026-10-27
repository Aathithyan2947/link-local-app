import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../address/presentation/address_proof_gate.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/media/image_editor.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validation/content_limits.dart';
import '../../../core/widgets/input_formatters.dart';
import '../data/group_detail_models.dart';
import '../discovery_repository.dart';
import '../group_lists_refresh.dart';
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
  /// The server's rejection of a field, shown under it until that field is edited.
  Map<String, String> _serverErrors = const {};

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    if (g == null) return;
    _title.text = g.title;
    _description.text = g.description ?? '';
    _price.text = g.price != null ? ContentLimits.priceText(g.price!) : '';
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
    setState(() => _serverErrors = const {});
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
        ref.invalidateGroupLists(groupId: id);
        await ref.read(groupDetailProvider(id).future);
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        final id = await repo.createGroup(data);
        if (!mounted) return;
        // Shows under My Groups → Your Groups (and everywhere else) straight away.
        ref.invalidateGroupLists();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => GroupProfileScreen(id: id)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (handleAddressProofError(context, ApiException.from(e), action: 'start a group')) return;
      _showSubmitError(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// A rejected field goes under that field; anything else says what the server said, not a
  /// generic "Could not create group" (BUG-072).
  void _showSubmitError(Object e) {
    final err = ApiException.from(e);
    final fields = err.fieldErrors;
    if (fields.isNotEmpty) {
      setState(() => _serverErrors = fields);
      _formKey.currentState!.validate();
      return;
    }
    final fallback = widget.isEdit ? 'Could not save group' : 'Could not create group';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err.message == 'Something went wrong' ? fallback : err.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit Group' : 'Start a Group')),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _imagePicker(),
            const SizedBox(height: 16),
            _field(_title, 'Group name', serverKey: 'title',
                maxLength: ContentLimits.titleMax,
                formatters: [ContentLimits.titleInputFormatter],
                validator: (v) => ContentLimits.titleError('Group name', v)),
            const SizedBox(height: 12),
            _field(_description, 'Description / guidelines', serverKey: 'description', maxLines: 4,
                maxLength: ContentLimits.description, validator: ContentLimits.descriptionError),
            const SizedBox(height: 12),
            _field(_maxMembers, 'Max members (optional)', serverKey: 'maxMembers',
                keyboard: TextInputType.number, formatters: kIntegerInput, validator: ContentLimits.maxMembersError),
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
            if (_isPaid)
              _field(_price, 'Price (₹)', serverKey: 'price', keyboard: kDecimalKeyboard, formatters: kDecimalInput,
                  validator: (v) => ContentLimits.priceError(v, what: 'group')),
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

  /// A form field whose message comes from [validator] (the shared ContentLimits rules), or
  /// from the server for [serverKey] until the field is edited again.
  Widget _field(TextEditingController c, String label,
      {required String serverKey,
      required String? Function(String) validator,
      int maxLines = 1,
      int? maxLength,
      TextInputType? keyboard,
      List<TextInputFormatter>? formatters}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      // With a limit, the field shows "12/80" under it and stops at the limit (BUG-071).
      maxLength: maxLength,
      keyboardType: keyboard,
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label, errorMaxLines: 3),
      onChanged: (_) {
        if (_serverErrors.containsKey(serverKey)) {
          setState(() => _serverErrors = {..._serverErrors}..remove(serverKey));
        }
      },
      validator: (v) => _serverErrors[serverKey] ?? validator(v ?? ''),
    );
  }
}
