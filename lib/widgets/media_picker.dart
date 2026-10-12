import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;

import '../state/post_listing_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'pill_button.dart';

/// Gallery / camera / file pickers for the post-listing flow.
///
/// Photos are shrunk on the phone before upload (max 2000 px, JPEG 82%):
/// a 6 MB camera photo becomes ~400 KB, which keeps uploads fast and the free
/// Storage quota lasting. Every function returns null / empty when the user
/// cancels, and shows a snackbar for files that are too big.
class MediaPicker {
  MediaPicker._();

  static final ImagePicker _images = ImagePicker();

  static const int maxPhotoBytes = 10 * 1024 * 1024;
  static const int maxVideoBytes = 50 * 1024 * 1024;
  static const int maxDocBytes = 15 * 1024 * 1024;

  /// "Add photos": choose from the gallery (several at once) or take one.
  static Future<List<PickedFile>> photos(BuildContext context,
      {int limit = 30}) async {
    final source = await _chooseSource(context,
        galleryLabel: 'Choose from gallery', cameraLabel: 'Take a photo');
    if (source == null) return const [];
    try {
      final List<XFile> files;
      if (source == ImageSource.gallery) {
        files = await _images.pickMultiImage(
          maxWidth: 2000,
          maxHeight: 2000,
          imageQuality: 82,
          limit: limit < 2 ? null : limit,
        );
      } else {
        final one = await _images.pickImage(
          source: ImageSource.camera,
          maxWidth: 2000,
          maxHeight: 2000,
          imageQuality: 82,
        );
        files = one == null ? const [] : [one];
      }
      final out = <PickedFile>[];
      for (final f in files.take(limit)) {
        final bytes = await f.readAsBytes();
        if (bytes.length > maxPhotoBytes) {
          if (context.mounted) _tell(context, '${f.name} is over 10 MB — skipped.');
          continue;
        }
        out.add(PickedFile(
          bytes: bytes,
          name: _jpegName(f.name),
          mimeType: f.mimeType ?? 'image/jpeg',
        ));
      }
      return out;
    } catch (e) {
      if (context.mounted) _tell(context, _permissionHint(e));
      return const [];
    }
  }

  /// "Add video": up to 60 seconds, 50 MB.
  static Future<PickedFile?> video(BuildContext context) async {
    final source = await _chooseSource(context,
        galleryLabel: 'Choose a video', cameraLabel: 'Record a video');
    if (source == null) return null;
    try {
      final f = await _images.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60),
      );
      if (f == null) return null;
      final size = await f.length();
      if (size > maxVideoBytes) {
        if (context.mounted) {
          _tell(context,
              'That video is ${(size / 1048576).toStringAsFixed(0)} MB. Keep it under 50 MB (about 1 minute).');
        }
        return null;
      }
      return PickedFile(
        bytes: await f.readAsBytes(),
        name: f.name,
        mimeType: f.mimeType ?? _videoMime(f.name),
      );
    } catch (e) {
      if (context.mounted) _tell(context, _permissionHint(e));
      return null;
    }
  }

  /// A document: a PDF or image file, or a photo of the paper.
  static Future<PickedFile?> document(BuildContext context) async {
    final choice = await _sheet<String>(context, [
      const _Option('file', Icons.description_outlined, 'Choose a PDF or image'),
      const _Option('camera', Icons.photo_camera_outlined, 'Take a photo of it'),
    ]);
    if (choice == null) return null;
    if (choice == 'camera') {
      if (!context.mounted) return null;
      return photo(context, preferFront: false, cameraOnly: true);
    }
    try {
      final f = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'webp'],
      );
      if (f == null) return null;
      final size = await f.length() ?? 0;
      if (size > maxDocBytes) {
        if (context.mounted) _tell(context, 'That file is over 15 MB.');
        return null;
      }
      final bytes = await f.readAsBytes();
      if (bytes.length > maxDocBytes) {
        if (context.mounted) _tell(context, 'That file is over 15 MB.');
        return null;
      }
      return PickedFile(bytes: bytes, name: f.name, mimeType: null);
    } catch (e) {
      if (context.mounted) _tell(context, "Couldn't open that file.");
      return null;
    }
  }

  /// One photo — the ID sides (back camera) or the selfie (front camera).
  /// With [cameraOnly] false the user can also pick one from the gallery.
  static Future<PickedFile?> photo(
    BuildContext context, {
    required bool preferFront,
    bool cameraOnly = false,
  }) async {
    var source = ImageSource.camera;
    if (!cameraOnly) {
      final picked = await _chooseSource(context,
          galleryLabel: 'Choose from gallery', cameraLabel: 'Use the camera');
      if (picked == null) return null;
      source = picked;
    }
    try {
      final f = await _images.pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
        preferredCameraDevice:
            preferFront ? CameraDevice.front : CameraDevice.rear,
      );
      if (f == null) return null;
      return PickedFile(
        bytes: await f.readAsBytes(),
        name: _jpegName(f.name),
        mimeType: f.mimeType ?? 'image/jpeg',
      );
    } catch (e) {
      if (context.mounted) _tell(context, _permissionHint(e));
      return null;
    }
  }

  // --------------------------------------------------------------------------

  static Future<ImageSource?> _chooseSource(
    BuildContext context, {
    required String galleryLabel,
    required String cameraLabel,
  }) =>
      _sheet<ImageSource>(context, [
        _Option(ImageSource.gallery, Icons.photo_library_outlined, galleryLabel),
        _Option(ImageSource.camera, Icons.photo_camera_outlined, cameraLabel),
      ]);

  static Future<T?> _sheet<T>(BuildContext context, List<_Option<T>> options) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(),
              const SizedBox(height: 6),
              for (final o in options)
                InkWell(
                  onTap: () => Navigator.of(sheetContext).pop(o.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenPadding + 4, vertical: 16),
                    child: Row(
                      children: [
                        Icon(o.icon, color: AppColors.primary, size: 22),
                        const SizedBox(width: 14),
                        Text(o.label,
                            style: AppTextStyles.bodyStrong()
                                .copyWith(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  static void _tell(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navDark,
      ));
  }

  static String _permissionHint(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('denied') || s.contains('permission')) {
      return 'Allow camera / photos access for Home8 in your phone settings.';
    }
    return "Couldn't open the camera or gallery.";
  }

  /// image_picker re-encodes to JPEG when it resizes; name the file to match.
  static String _jpegName(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '$base.jpg';
  }

  static String _videoMime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.3gp')) return 'video/3gpp';
    if (n.endsWith('.webm')) return 'video/webm';
    if (n.endsWith('.mkv')) return 'video/x-matroska';
    return 'video/mp4';
  }
}

class _Option<T> {
  final T value;
  final IconData icon;
  final String label;
  const _Option(this.value, this.icon, this.label);
}
