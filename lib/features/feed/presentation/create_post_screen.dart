import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/media/image_editor.dart';
import '../../../core/theme/app_colors.dart';
import '../../discovery/discovery_repository.dart';
import '../data/feed_repository.dart';
import '../data/post_models.dart';

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
      ref.invalidate(feedProvider);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create post')));
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
            decoration: const InputDecoration(
              hintText: 'What would you like to share with your neighbourhood?',
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
