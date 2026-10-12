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
import 'step_location_screen.dart';
import 'step_media.dart';
import 'step_permit.dart';
import 'step_reels.dart';

/// "Post a listing" — the six-step flow from the prototype:
///
///   1 Basics → 2 Details & price → 3 Photos → 4 Location → 5 Verify →
///   6 Reels package → Preview → Submitted.
///
/// One route for all six steps: the header, progress bar and footer stay put
/// and only the body changes. Everything is saved in Supabase: "Save" stores a
/// draft, "Publish listing" (on Preview) sends it for review.
class PostListingFlow extends StatefulWidget {
  /// Set when reopening a listing from My Listings ("Continue editing").
  final ListingDraft? initialDraft;

  /// The account is waiting for verification: everything works and drafts
  /// save, but Publish is locked until you approve the account.
  final bool accountPending;

  const PostListingFlow({
    super.key,
    this.initialDraft,
    this.accountPending = false,
  });

  @override
  State<PostListingFlow> createState() => _PostListingFlowState();
}

class _PostListingFlowState extends State<PostListingFlow> {
  late final PostListingController _controller;
  final ScrollController _scroll = ScrollController();

  /// Reels card currently highlighted (Unlimited is pre-selected, as designed).
  late ReelsPackage _reelsChoice;

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    final appState = scope.appState;
    final user = scope.auth.user;
    final profile = user?.listerProfile;

    final seed = widget.initialDraft ??
        ListingDraft(
          countryCode: appState.market.code,
          city: appState.marketCity,
          currency: appState.currency,
          contactEmail: user?.email ?? '',
          contactPhone: user?.phone ?? '',
          contactWhatsapp: user?.phone ?? '',
        );

    _reelsChoice = seed.reelsPackage ?? ReelsPackage.unlimited30d;

    _controller = PostListingController(
      scope.repository,
      initial: seed,
      accountPending: widget.accountPending,
      lister: user == null
          ? null
          : ListerSummary(
              name: user.name,
              agency: profile?.organisation ?? '',
              avatarUrl: user.avatarUrl,
              type: profile?.type.name ?? 'individual',
            ),
    );
    _controller.addListener(_onStep);
  }

  PostStep? _lastStep;

  /// New step → back to the top of the page.
  void _onStep() {
    if (_lastStep != _controller.step) {
      _lastStep = _controller.step;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onStep);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _tell(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navDark,
      ));
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
    if (choice == 'save') {
      if (_controller.anyUploading) {
        _tell('Wait for the uploads to finish, then save.');
        return;
      }
      final ok = await _controller.saveDraft();
      if (!mounted) return;
      if (!ok) {
        _tell("Couldn't save — ${_controller.errorMessage}");
        return;
      }
    } else {
      _controller.discardUploads();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_controller.anyUploading) {
      _tell('Wait for the uploads to finish, then save.');
      return;
    }
    final ok = await _controller.saveDraft();
    if (!mounted) return;
    _tell(ok ? 'Draft saved' : "Couldn't save — ${_controller.errorMessage}");
  }

  void _back() {
    if (!_controller.back()) _close();
  }

  Future<void> _advance() async {
    // Tapped before the step is complete: say exactly what's missing.
    if (!_controller.canAdvance) {
      final missing = _controller.draft.missingFor(_controller.step);
      _tell(_controller.anyUploading
          ? 'Wait for the uploads to finish.'
          : missing.isEmpty
              ? 'Complete this step to continue.'
              : 'Still needed: ${missing.join(', ')}');
      return;
    }
    if (_controller.next()) return;
    await _openPreview();
  }

  Future<void> _openPreview() async {
    await Navigator.of(context).push<MyListing>(
      MaterialPageRoute(
        builder: (_) => ListingPreviewScreen(controller: _controller),
      ),
    );
  }

  /// "Purchase the Package". Payments aren't connected yet: the choice is
  /// saved on the listing and the team activates it.
  Future<void> _purchaseReels() async {
    _controller.edit((d) => d.copyWith(reelsPackage: _reelsChoice));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('${_reelsChoice.title} — AED ${_reelsChoice.priceAed}',
            style: AppTextStyles.h2()),
        content: Text(
          "Online payment isn't available yet. We've added this package to "
          "your listing and our team will contact you to complete the "
          'payment and switch it on.',
          style: AppTextStyles.body(color: AppColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Continue',
                style: AppTextStyles.bodyStrong(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (mounted) await _openPreview();
  }

  Future<void> _skipReels() async {
    _controller.edit((d) => d.copyWith(clearReelsPackage: true));
    await _openPreview();
  }

  String get _ctaLabel => switch (_controller.step) {
        PostStep.basics => 'Next — Details',
        PostStep.details => 'Next — Photos',
        PostStep.media => 'Next — Location',
        PostStep.location => 'Next — Verify',
        PostStep.permit => 'Submit for review',
        PostStep.reels => 'Purchase the Package',
      };

  Widget _body(PostStep step) => switch (step) {
        PostStep.basics => StepBasics(controller: _controller),
        PostStep.details => StepDetails(controller: _controller),
        PostStep.media => StepMedia(controller: _controller),
        PostStep.location => StepLocation(controller: _controller),
        PostStep.permit => StepPermit(controller: _controller),
        PostStep.reels => StepReels(
            controller: _controller,
            selected: _reelsChoice,
            onSelect: (p) => setState(() => _reelsChoice = p),
          ),
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
              final uploading = _controller.anyUploading;
              return Column(
                children: [
                  _FlowHeader(
                    step: step,
                    saving: _controller.saving,
                    // No "Save" on the last two steps, as designed.
                    showSave: step != PostStep.permit && step != PostStep.reels,
                    onBack: _back,
                    onClose: _close,
                    onSave: _save,
                  ),
                  Expanded(
                    child: ListView(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
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
                              .copyWith(fontSize: 12.5, letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 6),
                        Text(step.title,
                            style:
                                AppTextStyles.display().copyWith(fontSize: 27)),
                        const SizedBox(height: 20),
                        _body(step),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding, 6, AppSpacing.screenPadding, 12),
                    child: step == PostStep.reels
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PrimaryButton(
                                label: _ctaLabel,
                                color: AppColors.amber,
                                onTap: _purchaseReels,
                              ),
                              const SizedBox(height: 6),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _skipReels,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Text(
                                    'Skip Reels',
                                    style: AppTextStyles.bodyStrong().copyWith(
                                      fontSize: 16,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Opacity(
                            // Looks disabled until the step is complete, but
                            // stays tappable so it can say what's missing.
                            opacity: _controller.canAdvance ? 1 : 0.45,
                            child: PrimaryButton(
                              label: uploading ? 'Uploading…' : _ctaLabel,
                              glow: _controller.canAdvance,
                              onTap: _advance,
                            ),
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

/// ✕ / ← · "Post a listing" · Save, with the six-segment progress bar.
class _FlowHeader extends StatelessWidget {
  final PostStep step;
  final bool saving;
  final bool showSave;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final VoidCallback onSave;

  const _FlowHeader({
    required this.step,
    required this.saving,
    required this.showSave,
    required this.onBack,
    required this.onClose,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final isFirst = step == PostStep.basics;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              // Same width as the Save slot, so the title stays centred.
              SizedBox(
                width: 72,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: isFirst ? onClose : onBack,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        isFirst
                            ? Icons.close_rounded
                            : Icons.arrow_back_rounded,
                        color: AppColors.ink,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text('Post a listing',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.h1().copyWith(fontSize: 21)),
              ),
              SizedBox(
                width: 72,
                child: !showSave
                    ? null
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: saving ? null : onSave,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: saving
                              ? const Align(
                                  alignment: Alignment.centerRight,
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          AppColors.inkMuted),
                                    ),
                                  ),
                                )
                              : Text('Save',
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: AppTextStyles.bodyStrong(
                                          color: AppColors.inkMuted)
                                      .copyWith(fontSize: 16)),
                        ),
                      ),
              ),
            ],
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: StepProgressBar(current: step),
        ),
      ],
    );
  }
}

/// Six segments; filled ones are teal.
class StepProgressBar extends StatelessWidget {
  final PostStep current;
  const StepProgressBar({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    final count = PostStep.numbered.length;
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 5,
              decoration: BoxDecoration(
                color: i < current.number ? AppColors.primary : AppColors.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (i != count - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}
