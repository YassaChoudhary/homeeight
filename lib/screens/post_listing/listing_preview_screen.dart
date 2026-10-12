import 'package:flutter/material.dart';

import '../../models/listing_draft.dart';
import '../../models/my_listing.dart';
import '../../models/property.dart';
import '../../state/post_listing_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/listing_card.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/property_image.dart';
import 'listing_submitted_screen.dart';
import '../../state/app_scope.dart';
import '../property_detail_screen.dart';

/// Screen 38 — "Preview".
///
/// ## The card is the real card
///
/// The amber banner promises "this is exactly what buyers will see", so the
/// preview has to be built from the same pieces the search results are: the
/// same `PropertyImage`, the same `VerifiedPill`, the same price formatting.
/// A hand-drawn approximation would drift from the real card within a week and
/// quietly make the promise false.
///
/// ## Edit chips jump, they don't rewind
///
/// Tapping "Photos" goes straight to the photos step and comes back here. The
/// user has already reached the end; making them walk forward through the
/// remaining steps again to fix one field is how people abandon a listing.
class ListingPreviewScreen extends StatefulWidget {
  final PostListingController controller;

  const ListingPreviewScreen({super.key, required this.controller});

  @override
  State<ListingPreviewScreen> createState() => _ListingPreviewScreenState();
}

class _ListingPreviewScreenState extends State<ListingPreviewScreen> {
  Future<void> _editStep(PostStep step) async {
    // Sends the stepper to that step and unwinds this route, so the user is
    // back in the flow rather than looking at the form through a preview.
    widget.controller.goTo(step);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _publish() async {
    final listing = await widget.controller.submit();
    if (!mounted) return;

    if (listing == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(widget.controller.errorMessage),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.navDark,
          ),
        );
      return;
    }

    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) => ListingSubmittedScreen(listing: listing),
      ),
    );
  }

  Future<void> _saveDraft() async {
    final ok = await widget.controller.saveDraft();
    if (!mounted) return;
    if (ok) {
      // Pops with no result: the flow closes, and My Listings will show it in
      // the Draft tab.
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text("Couldn't save — ${widget.controller.errorMessage}"),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navDark,
        ),
      );
  }

  /// The real listing page, built from the draft.
  void _openFullPreview(ListingDraft draft) {
    final user = AppScope.authOf(context).user;
    final lister = widget.controller.lister;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(
          propertyId: draft.id ?? 'preview',
          preloaded: draft.toPreviewProperty(
            agentName: lister?.name ?? user?.name ?? '',
            agency: (lister?.agency.isNotEmpty ?? false)
                ? lister!.agency
                : ((lister?.type ?? 'individual') == 'individual'
                    ? 'Property owner'
                    : ''),
            avatarUrl: lister?.avatarUrl,
            fairPrice: widget.controller.guidance?.valueOrNull,
          ),
          previewOnly: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final draft = widget.controller.draft;
            final ready = draft.readyToPublish;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).maybePop(),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.arrow_back_rounded,
                              color: AppColors.ink, size: 24),
                        ),
                      ),
                      Expanded(
                        child: Text('Preview',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.h1().copyWith(fontSize: 21)),
                      ),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding, 6, AppSpacing.screenPadding, 24),
                    children: [
                      const InfoNote(
                        tone: NoteTone.warning,
                        icon: Icons.visibility_outlined,
                        message: 'This is exactly what buyers will see',
                      ),
                      const SizedBox(height: 16),
                      // Tap the card to see the full listing page as
                      // buyers will.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openFullPreview(draft),
                        child: _PreviewCard(draft: draft),
                      ),
                      const SizedBox(height: 24),
                      const FieldLabel('Edit a step'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final step in PostStep.chipOrder)
                            _EditChip(
                              label: step.chipLabel,
                              // An incomplete step gets an amber dot rather
                              // than a pencil, so the thing blocking publish is
                              // findable without reading the banner below.
                              complete: draft.completed(step),
                              onTap: () => _editStep(step),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (widget.controller.accountPending)
                        const InfoNote(
                          tone: NoteTone.warning,
                          icon: Icons.schedule_rounded,
                          message: 'Your account is waiting for verification. '
                              'Save this as a draft — you can publish it from '
                              'My Listings once you\'re approved.',
                        )
                      else if (ready)
                        const InfoNote(
                          tone: NoteTone.success,
                          icon: Icons.check_rounded,
                          message: 'All checks passed — ready to publish.',
                        )
                      else
                        InfoNote(
                          tone: NoteTone.warning,
                          icon: Icons.error_outline_rounded,
                          message:
                              'Still needed: ${draft.missingSummary}. You can '
                              'save this as a draft and finish later.',
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding, 4, AppSpacing.screenPadding, 12),
                  child: Column(
                    children: [
                      PrimaryButton(
                        label: 'Publish listing',
                        loading: widget.controller.submitting,
                        onTap: ready && !widget.controller.accountPending
                            ? _publish
                            : null,
                      ),
                      const SizedBox(height: 4),
                      TertiaryButton(
                        label: 'Save as draft',
                        onTap: widget.controller.saving ? null : _saveDraft,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The buyer-facing card, assembled from the draft.
class _PreviewCard extends StatelessWidget {
  final ListingDraft draft;

  const _PreviewCard({required this.draft});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final photoCount = draft.photos.length;
    // Same rule as review: deed + ID → Verified badge.
    final verified = draft.titleDeed != null && draft.idScanned;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg + 6),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            child: PropertyImage(
              seed: draft.gradientSeed,
              url: draft.coverUrl,
              decodeWidth: width,
              child: Stack(
                children: [
                  if (photoCount > 0)
                    PositionedDirectional(
                      start: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '1 / $photoCount',
                          style: AppTextStyles.micro(color: Colors.white)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  PositionedDirectional(
                    end: 12,
                    top: 12,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.32),
                        shape: BoxShape.circle,
                      ),
                      // Inert on purpose: this is a picture of the buyer's
                      // save button, not a save button. Wiring it would let a
                      // seller save their own unpublished listing.
                      child: const Icon(Icons.favorite_border_rounded,
                          color: Colors.white, size: 17),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        draft.title.trim().isEmpty
                            ? 'Untitled listing'
                            : draft.title,
                        style: AppTextStyles.h2().copyWith(fontSize: 17.5),
                      ),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 10),
                      const VerifiedPill(),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(draft.specLine, style: AppTextStyles.caption()),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    style: AppTextStyles.display().copyWith(fontSize: 20),
                    children: [
                      TextSpan(
                        text: (draft.price ?? 0) > 0
                            ? '${draft.currency} ${formatThousands(draft.price!)}'
                            : 'Price not set',
                      ),
                      TextSpan(
                        text: [
                          if (draft.purpose == Purpose.rent &&
                              draft.period != null &&
                              (draft.price ?? 0) > 0)
                            ' / ${draft.period!.label}',
                          if (draft.pricePerUnit > 0)
                            ' · ${formatThousands(draft.pricePerUnit)}/${draft.areaUnit.label}',
                        ].join(),
                        style: AppTextStyles.caption()
                            .copyWith(fontSize: 14.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditChip extends StatelessWidget {
  final String label;
  final bool complete;
  final VoidCallback onTap;

  const _EditChip({
    required this.label,
    required this.complete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: complete ? AppColors.line : AppColors.warning,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppTextStyles.bodyStrong().copyWith(fontSize: 15)),
            const SizedBox(width: 8),
            Icon(
              complete ? Icons.edit_outlined : Icons.error_outline_rounded,
              size: 15,
              color: complete ? AppColors.primary : AppColors.warning,
            ),
          ],
        ),
      ),
    );
  }
}
