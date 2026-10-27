import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../address/presentation/address_proof_gate.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/media/image_editor.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validation/content_limits.dart';
import '../../discovery/discovery_repository.dart';
import '../data/feed_repository.dart';
import '../data/post_models.dart';
import '../post_lists_refresh.dart';

/// Compose a community post: pick a type, write text, optionally attach a photo.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _text = TextEditingController();
  String _type = 'ask_help';
  XFile? _image;
  bool _submitting = false;
  /// Over the limit while typing (BUG-070), or the server's message after a rejected post.
  String? _textError;

  @override
  void dispose() {
    _text.dispose();
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
    if (_text.text.trim().isEmpty && _image == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Write something or add a photo')));
      return;
    }
    final tooLong = ContentLimits.postTextError(_text.text);
    if (tooLong != null) {
      setState(() => _textError = tooLong);
      return;
    }
    setState(() => _submitting = true);
    try {
      final photoUrls = <String>[];
      if (_image != null) {
        final url = await ref.read(discoveryRepositoryProvider).uploadImage(_image!.path, type: 'post');
        photoUrls.add(url);
      }
      await ref.read(feedRepositoryProvider).createPost(
            postType: _type,
            text: _text.text,
            photoUrls: photoUrls,
          );
      if (!mounted) return;
      ref.invalidatePostLists();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final err = ApiException.from(e);
      if (handleAddressProofError(context, err, action: 'create a post')) return;
      final textMsg = err.fieldError('textContent');
      if (textMsg != null) {
        setState(() => _textError = textMsg);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err.message == 'Something went wrong' ? 'Could not create post' : err.message),
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Create a Post'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Post', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Post type', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: postTypeLabels.entries
                .map((e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _type == e.key,
                      onSelected: (_) => setState(() => _type = e.key),
                      selectedColor: AppColors.primarySurface,
                      labelStyle: TextStyle(
                          color: _type == e.key ? AppColors.primary : AppColors.textSecondary,
                          fontWeight: FontWeight.w600),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            // Counts up to the limit and keeps typing possible past it, so the message under the
            // field explains why Post won't go instead of input silently stopping.
            maxLength: ContentLimits.postText,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            onChanged: (v) => setState(() => _textError = ContentLimits.postTextError(v)),
            decoration: InputDecoration(
              hintText: 'What would you like to share with your neighbourhood?',
              errorText: _textError,
            ),
          ),
          const SizedBox(height: 16),
          if (_image != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(_image!.path), height: 200, width: double.infinity, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => setState(() => _image = null),
                    child: const CircleAvatar(
                        radius: 14, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 16, color: Colors.white)),
                  ),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add a photo'),
            ),
        ],
      ),
    );
  }
}
