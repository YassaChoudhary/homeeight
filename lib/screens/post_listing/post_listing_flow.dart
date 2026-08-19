import 'package:flutter/material.dart';

import '../../models/listing_draft.dart';
import '../../models/my_listing.dart';
import '../../state/app_scope.dart';
import '../../state/post_listing_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/pill_button.dart';
import 'listing_preview_screen.dart';
import 'step_basics.dart';
import 'step_details.dart';
import 'step_media.dart';
import 'step_permit.dart';

/// Screens 33–37 — the guided "Post a listing" stepper.
///
/// ## One route, four steps
///
/// The steps are not separate routes. The header, progress bar and footer CTA
/// are identical across all four, and pushing a route per step would rebuild
/// them each time and put four entries on the back stack for what the user
/// experiences as one screen. The host owns the chrome; each step contributes
/// only its fields.
///
/// The location screen (36) *is* a pushed route, because it's reached from the
/// Map link on Basics and returns a value. Same for Preview (38).
///
/// ## Closing
///
/// `X` never discards silently. If anything has been entered, it offers to keep
/// the draft — which is the whole point of the Draft tab on My Listings.
class PostListingFlow extends StatefulWidget {
  /// Set when reopening an existing draft from "Continue editing".
  final ListingDraft? initialDraft;

  const PostListingFlow({super.key, this.initialDraft});

  @override
  State<PostListingFlow> createState() => _PostListingFlowState();
}

class _PostListingFlowState extends State<PostListingFlow> {
  late final PostListingController _controller;

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    final appState = scope.appState;

    // Seeded from the user's chosen market rather than hardcoded, so someone
    // browsing Pakistan doesn't have to change the country and currency on
    // every listing they post.
    final seed = widget.initialDraft ??
        ListingDraft(
          countryCode: appState.market.code,
          city: appState.marketCity,
          currency: appState.currency,
        );

    _controller = PostListingController(scope.repository, initial: seed);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final draft = _controller.draft;
    final hasContent = draft.propertyType != null ||
        draft.title.trim().isNotEmpty ||
        (draft.price ?? 0) > 0 ||
        draft.photos.isNotEmpty;

    if (!hasContent) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('Save this listing?', style: AppTextStyles.h2()),
        content: Text(
          "It'll wait in your drafts so you can finish it later.",
          style: AppTextStyles.body(color: AppColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: Text('Discard',
                style: AppTextStyles.bodyStrong(color: AppColors.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: Text('Save draft',
                style: AppTextStyles.bodyStrong(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;
    if (choice == 'save') await _controller.saveDraft();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final ok = await _controller.saveDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(ok ? 'Draft saved' : "Couldn't save — try again"),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navDark,
        ),
      );
  }

  void _back() {
    if (!_controller.back()) _close();
  }

  Future<void> _advance() async {
    // At the end of the numbered steps, the next thing is the preview — which
    // is a route rather than a step because it's also reachable from My
    // Listings later.
    if (_controller.next()) return;

    final result = await Navigator.of(context).push<MyListing>(
      MaterialPageRoute(
        builder: (_) => ListingPreviewScreen(controller: _controller),
      ),
    );

    // The preview screen pops with the published listing on success; that
    // means the flow itself is done and should get out of the way.
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  /// Named for what happens next rather than "Next", which is what the design
  /// shows and what stops a four-step form feeling open-ended.
  String get _ctaLabel => switch (_controller.step) {
        PostStep.basics => 'Next — Details',
        PostStep.location => 'Next — Details',
        PostStep.details => 'Next — Photos',
        PostStep.media => 'Next — Verification',
        PostStep.permit => 'Next — Preview',
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final step = _controller.step;
              return Column(
                children: [
                  _FlowHeader(
                    step: step,
                    saving: _controller.saving,
                    onBack: _back,
                    onClose: _close,
                    onSave: _save,
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding,
                        18,
                        AppSpacing.screenPadding,
                        24,
                      ),
                      children: [
                        Text(
                          'STEP ${step.number} OF ${PostStep.numbered.length}',
                          style: AppTextStyles.micro(color: AppColors.primary)
                              .copyWith(
                                  fontSize: 12.5, letterSpacing: 0.8),
                        ),
                        const SizedBox(height: 6),
                        Text(step.title,
                            style:
                                AppTextStyles.display().copyWith(fontSize: 27)),
                        const SizedBox(height: 20),
                        switch (step) {
                          PostStep.basics ||
                          PostStep.location =>
                            StepBasics(controller: _controller),
                          PostStep.details =>
                            StepDetails(controller: _controller),
                          PostStep.media => StepMedia(controller: _controller),
                          PostStep.permit =>
                            StepPermit(controller: _controller),
                        },
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding, 6, AppSpacing.screenPadding, 12),
                    child: PrimaryButton(
                      label: _ctaLabel,
                      // Disabled rather than hidden, so the CTA doesn't jump
                      // around as fields are filled in.
                      onTap: _controller.canAdvance ? _advance : null,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Close · title · Save, with the four-segment progress bar under it.
class _FlowHeader extends StatelessWidget {
  final PostStep step;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final VoidCallback onSave;

  const _FlowHeader({
    required this.step,
    required this.saving,
    required this.onBack,
    required this.onClose,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final isFirst = step == PostStep.basics || step == PostStep.location;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                // The first step shows an X because there's nothing behind it
                // in the flow; later steps show a back arrow. Same slot, so
                // the title never shifts.
                onTap: isFirst ? onClose : onBack,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    isFirst ? Icons.close_rounded : Icons.arrow_back_rounded,
                    color: AppColors.ink,
                    size: 24,
                  ),
                ),
              ),
              Expanded(
                child: Text('Post a listing',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.h1().copyWith(fontSize: 21)),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: saving ? null : onSave,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.inkMuted),
                          ),
                        )
                      : Text('Save',
                          style: AppTextStyles.bodyStrong(
                                  color: AppColors.inkMuted)
                              .copyWith(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding),
          child: StepProgressBar(current: step),
        ),
      ],
    );
  }
}

/// Four segments; filled ones are teal, the rest are the line token.
///
/// Public because the location screen renders it too — it's a sub-screen of
/// step 1 and has to show the same progress, or it reads as a step the user
/// has somehow skipped into.
class StepProgressBar extends StatelessWidget {
  final PostStep current;
  const StepProgressBar({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < PostStep.numbered.length; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 4,
              decoration: BoxDecoration(
                color:
                    i < current.number ? AppColors.primary : AppColors.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (i != PostStep.numbered.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}
