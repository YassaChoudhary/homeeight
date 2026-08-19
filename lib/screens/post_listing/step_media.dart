import 'package:flutter/material.dart';

import '../../models/listing_draft.dart';
import '../../state/post_listing_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/property_image.dart';

/// Screen 35 — "Add photos & media", the fields of step 3.
///
/// ## No picker yet, and why the flow still works
///
/// `image_picker` isn't a dependency. Adding it needs an Android manifest entry
/// and an iOS `Info.plist` usage string, neither of which can be verified from
/// the environment this was written in — and a listing flow that crashes on the
/// photo step is worse than one that mocks it.
///
/// So "Add photos" attaches a `DraftPhoto` with a gradient seed instead of a
/// file. `PropertyImage` already renders those as distinct brand gradients (no
/// photography shipped with the app at all), so the grid, the cover badge, the
/// remove buttons, the 8-photo nudge and the completeness rule are all
/// exercised for real.
///
/// To wire the real thing: replace the body of [_addPhoto] with the picker call
/// and set `DraftPhoto.localPath`. Nothing else on this screen changes.
class StepMedia extends StatelessWidget {
  final PostListingController controller;

  const StepMedia({super.key, required this.controller});

  /// Eight is where the enquiry numbers actually move, so it's the number the
  /// copy quotes and the number the progress hint counts towards.
  static const int _targetPhotos = 8;

  void _addPhoto() {
    controller.edit((draft) {
      final next = List<DraftPhoto>.from(draft.photos);
      next.add(
        DraftPhoto(
          id: 'ph_${DateTime.now().microsecondsSinceEpoch}',
          // Spread the gradients so consecutive additions look different.
          seed: (draft.photos.length * 3 + 1),
        ),
      );
      return draft.copyWith(photos: next);
    });
  }

  void _removePhoto(String id) {
    controller.edit((draft) {
      final next = draft.photos.where((p) => p.id != id).toList();
      // Removing the cover has to move the cover, or coverIndex points past
      // the end of the list and the preview renders the wrong photo.
      final removedIndex = draft.photos.indexWhere((p) => p.id == id);
      var cover = draft.coverIndex;
      if (removedIndex <= cover && cover > 0) cover -= 1;
      return draft.copyWith(
        photos: next,
        coverIndex: next.isEmpty ? 0 : cover.clamp(0, next.length - 1),
      );
    });
  }

  void _setCover(int index) =>
      controller.edit((draft) => draft.copyWith(coverIndex: index));

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final photos = draft.photos;
    final cover = draft.coverIndex.clamp(0, photos.isEmpty ? 0 : photos.length - 1);
    final remaining = _targetPhotos - photos.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Listings with $_targetPhotos+ photos get 3× more enquiries.',
          style: AppTextStyles.body(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 18),
        if (photos.isEmpty)
          DashedAddTile(
            label: 'Add your first photo',
            icon: Icons.add_photo_alternate_outlined,
            height: 190,
            inline: false,
            onTap: _addPhoto,
          )
        else ...[
          // The cover gets the full width because it's the only photo most
          // people will ever see — it's the card image in every search result.
          _PhotoFrame(
            photo: photos[cover],
            height: 190,
            isCover: true,
            onRemove: () => _removePhoto(photos[cover].id),
          ),
          const SizedBox(height: 12),
          _PhotoGrid(
            photos: photos,
            coverIndex: cover,
            onRemove: _removePhoto,
            onSetCover: _setCover,
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DashedAddTile(
                label: 'Add photos',
                icon: Icons.add_rounded,
                height: 108,
                inline: false,
                onTap: _addPhoto,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DashedAddTile(
                label: 'Add video',
                icon: Icons.play_arrow_rounded,
                tint: AppColors.amber,
                tintBg: const Color(0xFFFCEBD2),
                height: 108,
                inline: false,
                // Video goes to Cloudflare Stream rather than Supabase Storage
                // (transcoding and adaptive bitrate), so this stays a stub
                // until that account exists. Flipping the flag lets the rest of
                // the flow — the preview badge, the submitted card — behave as
                // though a video is attached.
                onTap: () => controller
                    .edit((d) => d.copyWith(hasVideo: !d.hasVideo)),
              ),
            ),
          ],
        ),
        if (draft.hasVideo) ...[
          const SizedBox(height: 12),
          const UploadedRow(
            fileName: 'Walkthrough video',
            statusLine: 'Attached · uploads on publish',
            icon: Icons.videocam_outlined,
            showTick: true,
          ),
        ],
        const SizedBox(height: 16),
        _TourRow(
          booked: draft.tourBooked,
          onBook: () =>
              controller.edit((d) => d.copyWith(tourBooked: !d.tourBooked)),
        ),
        const SizedBox(height: 16),
        const InfoNote(
          tone: NoteTone.warning,
          icon: Icons.error_outline_rounded,
          message: 'Photos are auto-checked — watermarked or stolen images '
              'will fail verification.',
        ),
        if (photos.isNotEmpty && remaining > 0) ...[
          const SizedBox(height: 12),
          Text(
            '$remaining more to reach $_targetPhotos.',
            style: AppTextStyles.caption(),
          ),
        ],
      ],
    );
  }
}

/// The secondary photo strip under the cover.
class _PhotoGrid extends StatelessWidget {
  final List<DraftPhoto> photos;
  final int coverIndex;
  final ValueChanged<String> onRemove;
  final ValueChanged<int> onSetCover;

  const _PhotoGrid({
    required this.photos,
    required this.coverIndex,
    required this.onRemove,
    required this.onSetCover,
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
        childAspectRatio: 1.28,
      ),
      itemBuilder: (context, i) {
        final index = others[i];
        return _PhotoFrame(
          photo: photos[index],
          height: 110,
          isCover: false,
          onRemove: () => onRemove(photos[index].id),
          onSetCover: () => onSetCover(index),
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

  const _PhotoFrame({
    required this.photo,
    required this.height,
    required this.isCover,
    required this.onRemove,
    this.onSetCover,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return SizedBox(
      height: height,
      child: PropertyImage(
        seed: photo.seed,
        url: photo.remoteUrl,
        borderRadius: BorderRadius.circular(AppRadius.md),
        // Always passed — decoding a full-res photo into a 110pt tile is the
        // single biggest source of dropped frames in this app.
        decodeWidth: isCover ? width : width / 2,
        child: Stack(
          children: [
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
            else if (onSetCover != null)
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
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The paid 360° capture upsell.
class _TourRow extends StatelessWidget {
  final bool booked;
  final VoidCallback onBook;

  const _TourRow({required this.booked, required this.onBook});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(AppRadius.sm),
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
          // No payment flow exists, so this records the intent and nothing
          // more. It reads as "requested", not "paid for", on purpose.
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
