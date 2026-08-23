import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Writes edited image bytes to a temp file and returns its path — for call
/// sites that keep a file path in local state (preview + eventual upload)
/// rather than raw bytes.
Future<String> writeEditedImageToTempFile(Uint8List bytes) async {
  final file = File('${Directory.systemTemp.path}/edited_${DateTime.now().microsecondsSinceEpoch}.jpg');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// Opens a crop/rotate editor for picked image bytes.
///
/// Returns the edited bytes, or `null` if the user cancelled — callers should
/// treat that identically to a cancelled pick (abort, no upload).
Future<Uint8List?> editPickedImageBytes(
  BuildContext context,
  Uint8List bytes, {
  bool lockToSquare = false,
}) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      builder: (_) => _ImageEditScreen(bytes: bytes, lockToSquare: lockToSquare),
      fullscreenDialog: true,
    ),
  );
}

class _ImageEditScreen extends StatefulWidget {
  const _ImageEditScreen({required this.bytes, required this.lockToSquare});
  final Uint8List bytes;
  final bool lockToSquare;

  @override
  State<_ImageEditScreen> createState() => _ImageEditScreenState();
}

class _ImageEditScreenState extends State<_ImageEditScreen> {
  final _controller = CropController();
  late Uint8List _current = widget.bytes;
  bool _busy = false;

  void _rotate() {
    final decoded = img.decodeImage(_current);
    if (decoded == null) return;
    final rotated = img.copyRotate(decoded, angle: 90);
    final bytes = Uint8List.fromList(img.encodeJpg(rotated));
    setState(() => _current = bytes);
    _controller.image = bytes;
  }

  void _confirm() {
    setState(() => _busy = true);
    _controller.crop();
  }

  void _onCropped(CropResult result) {
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop(croppedImage);
      case CropFailure(:final cause):
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not edit photo: $cause')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Edit Photo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_left),
            onPressed: _busy ? null : _rotate,
            tooltip: 'Rotate',
          ),
          TextButton(
            onPressed: _busy ? null : _confirm,
            child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Crop(
        controller: _controller,
        image: _current,
        aspectRatio: widget.lockToSquare ? 1 : null,
        baseColor: Colors.black,
        progressIndicator: const Center(child: CircularProgressIndicator(color: Colors.white)),
        onCropped: _onCropped,
      ),
    );
  }
}
