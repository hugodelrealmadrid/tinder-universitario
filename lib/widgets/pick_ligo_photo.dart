import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Android delegates capture to its camera app. Web keeps the browser picker.
Future<XFile?> pickLigoPhoto(BuildContext context, ImagePicker picker) async {
  var source = ImageSource.gallery;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar fotografía'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return null;
    source = choice;
  }
  return picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
}
