import 'package:flutter/material.dart';

import '../../models/listing_draft.dart';
import '../../state/post_listing_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart' show AppRadius;
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/media_picker.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/property_image.dart';

/// Step 3 — "Add photos & media" (prototype screen 41).
///
/// Photos come from the gallery (several at once) or the camera, are shrunk
/// on the phone and upload to Supabase Storage straight away — each tile
/// shows the picked image with a spinner until it's up. A failed one shows
/// "Retry". The first photo (or the one marked) is the cover buyers see.
///
/// Video: up to 60 s / 50 MB, uploaded to Storage too.
/// 360° tour: a request we record ("Requested") — a person follows up.
class StepMedia extends StatelessWidget {
  final PostListingController controller;

  const StepMedia({super.key, required this.controller});

  static const int _targetPhotos = 8;

  Future<void> _addPhotos(BuildContext context) async {
    final room = PostListingController.maxPhotos - controller.draft.photos.length;
    if (room <= 0) {
      _tell(context, 'That\'s the maximum of ${PostListingController.maxPhotos} photos.');
      return;
    }
    final files = await MediaPicker.photos(context, limit: room);
    if (files.isEmpty) return;
    await controller.addPhotos(files);
    if (!context.mounted) return;
    if (controller.draft.photos.any((p) => p.state == PhotoUploadState.failed)) {
      _tell(context, controller.errorMessage);
    }
  }

  Future<void> _addVideo(BuildContext context) async {
    final file = await MediaPicker.video(context);
    if (file == null) return;
    final ok = await controller.uploadDoc(DocSlot.video, file);
    if (!ok && context.mounted) _tell(context, controller.errorMessage);
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

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final photos = draft.photos;
    final cover =
        draft.coverIndex.clamp(0, photos.isEmpty ? 0 : photos.length - 1);
    final videoUploading = controller.isUploading(DocSlot.video);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Listings with $_targetPhotos+ photos get 3× more enquiries.',
          style: AppTextStyles.body(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 18),
        if (photos.isNotEmpty) ...[
          _PhotoFrame(
            photo: photos[cover],
            height: 190,
            isCover: true,
            onRemove: () => controller.removePhoto(photos[cover].id),
            onRetry: () => controller.retryPhoto(photos[cover].id),
          ),
          const SizedBox(height: 12),
          _PhotoGrid(
            photos: photos,
            coverIndex: cover,
            onRemove: controller.removePhoto,
            onSetCover: controller.setCover,
            onRetry: controller.retryPhoto,
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: DashedAddTile(
                label: 'Add photos',
                icon: Icons.add_rounded,
                height: 108,
                inline: false,
                onTap: () => _addPhotos(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: videoUploading
                  ? const _BusyTile(label: 'Uploading video…')
                  : DashedAddTile(
                      label: draft.hasVideo ? 'Replace video' : 'Add video',
                      icon: Icons.play_arrow_rounded,
                      tint: AppColors.amber,
                      tintBg: const Color(0xFFFCEBD2),
                      height: 108,
                      inline: false,
                      onTap: () => _addVideo(context),
                    ),
            ),
          ],
        ),
        if (draft.video != null) ...[
          const SizedBox(height: 12),
          UploadedRow(
            fileName: 'Walkthrough video',
            statusLine: draft.video!.statusLine,
            icon: Icons.videocam_outlined,
            actionLabel: 'Remove',
            onAction: () => controller.removeDoc(DocSlot.video),
          ),
        ],
        const SizedBox(height: 16),
        _TourRow(
          booked: draft.tourBooked,
          onBook: () =>
              controller.edit((d) => d.copyWith(tourBooked: !d.tourBooked)),
        ),
        if (photos.isNotEmpty && draft.uploadedPhotoCount < 2) ...[
          const SizedBox(height: 14),
          Text('Add at least 2 photos to continue.',
              style: AppTextStyles.caption()),
        ],
      ],
    );
  }
}

class _BusyTile extends StatelessWidget {
  final String label;
  const _BusyTile({required this.label});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const DashedBorderPainter(),
      child: SizedBox(
        height: 108,
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.amber),
              ),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: AppTextStyles.bodyStrong(color: AppColors.amber)),
          ],
        ),
      ),
    );
  }
}

/// The photos under the cover, two per row.
class _PhotoGrid extends StatelessWidget {
  final List<DraftPhoto> photos;
  final int coverIndex;
  final ValueChanged<String> onRemove;
  final ValueChanged<int> onSetCover;
  final ValueChanged<String> onRetry;

  const _PhotoGrid({
    required this.photos,
    required this.coverIndex,
    required this.onRemove,
    required this.onSetCover,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final others = <int>[
      for (var i = 0; i < photos.length; i++)
        if (i != coverIndex) i,
    ];
    if (others.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: others.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemBuilder: (context, i) {
        final index = others[i];
        return _PhotoFrame(
          photo: photos[index],
          height: 110,
          isCover: false,
          onRemove: () => onRemove(photos[index].id),
          onSetCover: () => onSetCover(index),
          onRetry: () => onRetry(photos[index].id),
        );
      },
    );
  }
}

class _PhotoFrame extends StatelessWidget {
  final DraftPhoto photo;
  final double height;
  final bool isCover;
  final VoidCallback onRemove;
  final VoidCallback? onSetCover;
  final VoidCallback onRetry;

  const _PhotoFrame({
    required this.photo,
    required this.height,
    required this.isCover,
    required this.onRemove,
    required this.onRetry,
    this.onSetCover,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final bytes = photo.bytes;
    final decode = ((isCover ? width : width / 2) * dpr).round();

    return SizedBox(
      height: height,
      child: PropertyImage(
        seed: photo.seed,
        url: bytes == null ? photo.remoteUrl : null,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        decodeWidth: isCover ? width : width / 2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes,
                  fit: BoxFit.cover, cacheWidth: decode, gaplessPlayback: true),
            if (photo.state == PhotoUploadState.uploading)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            if (photo.state == PhotoUploadState.failed)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRetry,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 26),
                      const SizedBox(height: 4),
                      Text('Upload failed · Retry',
                          style: AppTextStyles.caption(color: Colors.white)
                              .copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            if (isCover)
              PositionedDirectional(
                start: 10,
                top: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('COVER',
                      style: AppTextStyles.micro(color: Colors.white)
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
              )
            else if (onSetCover != null &&
                photo.state == PhotoUploadState.done)
              PositionedDirectional(
                start: 8,
                bottom: 8,
                child: Pressable(
                  onTap: onSetCover,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('Make cover',
                        style: AppTextStyles.micro(color: Colors.white)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            PositionedDirectional(
              end: 8,
              top: 8,
              child: Pressable(
                onTap: onRemove,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 17),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "360° virtual tour — Book a Home8 capture visit — AED 149".
///
/// Payments aren't live, so "Book" records the request on the listing and a
/// person follows up; the button then reads "Requested".
class _TourRow extends StatelessWidget {
  final bool booked;
  final VoidCallback onBook;

  const _TourRow({
    required this.booked,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.threesixty_rounded,
                size: 24, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('360° virtual tour',
                    style: AppTextStyles.bodyStrong().copyWith(fontSize: 16)),
                const SizedBox(height: 2),
                Text('Book a Home8 capture visit — AED 149',
                    style: AppTextStyles.caption()),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Pressable(
            onTap: onBook,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: booked ? AppColors.primary : Colors.transparent,
                border: Border.all(color: AppColors.primary, width: 1.4),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                booked ? 'Requested' : 'Book',
                style: AppTextStyles.bodyStrong(
                  color: booked ? Colors.white : AppColors.primary,
                ).copyWith(fontSize: 14.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
