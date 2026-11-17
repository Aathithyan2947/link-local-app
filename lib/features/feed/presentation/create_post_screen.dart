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
import '../../../core/widgets/audience_picker.dart';
import '../../discovery/discovery_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../data/feed_repository.dart';
import '../data/post_models.dart';
import '../post_lists_refresh.dart';

/// Write a Post, as the Figma draws it (BUG-108): who it's for ("Post in", BUG-115), an
/// optional title, the type, the text, a photo or video, and whether replies notify you.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  String _type = 'general';
  String _audience = defaultAudience;
  XFile? _media;
  bool _isVideo = false;
  bool _notify = true;
  bool _submitting = false;
  /// Over the limit while typing (BUG-070), or the server's message after a rejected post.
  String? _textError;
  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: AppColors.primary),
              title: const Text('Photo'),
              onTap: () => Navigator.of(sheet).pop('photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined, color: AppColors.primary),
              title: const Text('Video'),
              subtitle: const Text('Up to 10 MB'),
              onTap: () => Navigator.of(sheet).pop('video'),
            ),
          ],
        ),
      ),
    );
    if (kind == 'photo') await _pickPhoto();
    if (kind == 'video') await _pickVideo();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final edited = await editPickedImageBytes(context, bytes);
    if (edited == null) return;
    final path = await writeEditedImageToTempFile(edited);
    setState(() {
      _media = XFile(path);
      _isVideo = false;
    });
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 1));
    if (picked == null || !mounted) return;
    // The server stops uploads at 10 MB; say so here instead of after a long upload.
    if (await picked.length() > ContentLimits.uploadBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Videos can be up to 10 MB. Try a shorter clip.')),
      );
      return;
    }
    setState(() {
      _media = picked;
      _isVideo = true;
    });
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty && _text.text.trim().isEmpty && _media == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write something or add a photo or video')),
      );
      return;
    }
    final tooLong = ContentLimits.postTextError(_text.text);
    if (tooLong != null) {
      setState(() => _textError = tooLong);
      return;
    }
    setState(() => _submitting = true);
    try {
      final media = <PostMedia>[];
      if (_media != null) {
        final url = await ref.read(discoveryRepositoryProvider).uploadImage(_media!.path, type: 'post');
        media.add(PostMedia(mediaType: _isVideo ? 'video' : 'photo', url: url));
      }
      await ref.read(feedRepositoryProvider).createPost(
            postType: _type,
            title: _title.text,
            text: _text.text,
            audience: _audience,
            notifyReplies: _notify,
            media: media,
          );
      if (!mounted) return;
      ref.invalidatePostLists();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final err = ApiException.from(e);
      if (handleAddressProofError(context, err, action: 'create a post')) return;
      final textMsg = err.fieldError('textContent');
      final titleMsg = err.fieldError('title');
      if (textMsg != null || titleMsg != null) {
        setState(() {
          _textError = textMsg;
          _titleError = titleMsg;
        });
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
    final place = ref.watch(myProfileProvider).asData?.value.place;
    final options = audienceOptions(building: place?.building, lane: place?.lane, area: place?.area, city: place?.city);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: AppColors.ink),
                  ),
                  Flexible(
                    child: AudiencePicker(
                      label: 'Post in',
                      value: _audience,
                      options: options,
                      onChanged: (v) => setState(() => _audience = v),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                children: [
                  Row(
                    children: [
                      const Text('Title',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink)),
                      const Spacer(),
                      Text('${_title.text.characters.length}/${ContentLimits.postTitle}',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    // Stops at 100, like the other titles (BUG-071); the counter above shows it.
                    inputFormatters: [LengthLimitingTextInputFormatter(ContentLimits.postTitle)],
                    onChanged: (_) => setState(() => _titleError = null),
                    decoration: InputDecoration(
                      hintText: "What's your post about?",
                      prefixIcon: const Icon(Icons.chat_bubble_outline, color: AppColors.textSecondary),
                      errorText: _titleError,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Post type'),
                    items: [
                      for (final e in postTypeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? _type),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _text,
                    minLines: 5,
                    maxLines: 10,
                    textCapitalization: TextCapitalization.sentences,
                    // Counts up to the limit and keeps typing possible past it, so the message under
                    // the field explains why it won't post instead of input silently stopping.
                    maxLength: ContentLimits.postText,
                    maxLengthEnforcement: MaxLengthEnforcement.none,
                    onChanged: (v) => setState(() => _textError = ContentLimits.postTextError(v)),
                    decoration: InputDecoration(
                      hintText: 'Write your post....',
                      alignLabelWithHint: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 80),
                        child: Icon(Icons.edit_outlined, color: AppColors.textSecondary),
                      ),
                      errorText: _textError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_media != null) _MediaPreview(file: _media!, isVideo: _isVideo, onRemove: _removeMedia)
                  else _AddMediaTile(onTap: _pickMedia),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.divider),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(color: AppColors.primarySurface, shape: BoxShape.circle),
                        child: const Icon(Icons.notifications_rounded, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Notify me of replies',
                                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                            SizedBox(height: 2),
                            Text("You'll be notified when someone comments",
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      Switch(
                        value: _notify,
                        onChanged: (v) => setState(() => _notify = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded),
                  label: const Text('Post Discussion'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _removeMedia() => setState(() {
        _media = null;
        _isVideo = false;
      });
}

/// The Figma's dashed "Add Photo or Video" row.
class _AddMediaTile extends StatelessWidget {
  const _AddMediaTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorder(),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add Photo or Video', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('Add supporting files to explain',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({required this.file, required this.isVideo, required this.onRemove});
  final XFile file;
  final bool isVideo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: isVideo
              ? Container(
                  height: 120,
                  width: double.infinity,
                  color: AppColors.primarySurface,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_rounded, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Flexible(child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                )
              : Image.file(File(file.path), height: 200, width: double.infinity, fit: BoxFit.cover),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(
                radius: 14, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 16, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
