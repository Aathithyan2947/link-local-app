import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';

typedef PickedDoc = ({String name, Uint8List bytes});

/// Shows a sheet to pick a proof document via camera or device file,
/// returning the picked bytes + filename (or null if cancelled).
Future<PickedDoc?> pickProofDocument(BuildContext context) async {
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

  if (source == 'camera') return _fromCamera();
  if (source == 'file') return _fromFile();
  return null;
}

Future<PickedDoc?> _fromCamera() async {
  final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 75, maxWidth: 1600);
  if (shot == null) return null;
  return (name: shot.name, bytes: await shot.readAsBytes());
}

Future<PickedDoc?> _fromFile() async {
  final result = await FilePicker.pickFiles(
    withData: true,
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
  );
  final f = result?.files.single;
  if (f?.bytes == null) return null;
  return (name: f!.name, bytes: f.bytes!);
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

/// Selectable proof-type card (Utility Bills / Any Other Proof).
class ProofTypeCard extends StatelessWidget {
  const ProofTypeCard({
    super.key,
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
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
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
