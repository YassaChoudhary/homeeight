import 'package:flutter/material.dart';

import '../../models/my_listing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/property_image.dart';
import '../lister/my_listings_screen.dart';
import 'post_listing_flow.dart';

/// Screen 39 — "Listing submitted for review".
///
/// Full-bleed teal, which is the only screen in the app that does this. That's
/// deliberate: it's the end of a long form, and a coloured screen is how the
/// user knows the form is over without reading anything.
///
/// ## Both exits leave the flow behind
///
/// "Go to my dashboard" and "Post another listing" both use
/// `pushAndRemoveUntil`-style unwinding rather than pushing on top. Leaving the
/// finished stepper on the back stack means the system back gesture drops the
/// user into a form they've already submitted.
class ListingSubmittedScreen extends StatelessWidget {
  final MyListing listing;

  const ListingSubmittedScreen({super.key, required this.listing});

  void _toDashboard(BuildContext context) {
    // Unwind to whatever launched the flow, then open My Listings on top of it
    // — so Back from the dashboard returns to the app, not to the stepper.
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyListingsScreen()),
    );
  }

  void _postAnother(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PostListingFlow()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back from here has no sensible target — the stepper behind it is spent.
      // Sending it to the dashboard is the only non-confusing answer.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toDashboard(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF14A9AB), AppColors.primaryDark],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(14),
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.check_rounded,
                                  color: AppColors.primary, size: 38),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Listing submitted for review',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.display(color: Colors.white)
                                .copyWith(fontSize: 28, height: 34 / 28),
                          ),
                          const SizedBox(height: 14),
                          Text.rich(
                            TextSpan(
                              style: AppTextStyles.body(color: Colors.white70)
                                  .copyWith(fontSize: 15.5, height: 22 / 15.5),
                              children: const [
                                TextSpan(
                                  text: "We're checking your permit and "
                                      'photos. Most listings go live within ',
                                ),
                                TextSpan(
                                  text: '2 hours',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(text: ". We'll notify you."),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          _SubmittedCard(listing: listing),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 14),
                  child: Column(
                    children: [
                      _LightButton(
                        label: 'Go to my dashboard',
                        filled: true,
                        onTap: () => _toDashboard(context),
                      ),
                      const SizedBox(height: 12),
                      _LightButton(
                        label: 'Post another listing',
                        filled: false,
                        onTap: () => _postAnother(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Translucent summary of what was just submitted.
///
/// Shows the reference number, because that's the one thing the seller will be
/// asked for if they have to chase the review.
class _SubmittedCard extends StatelessWidget {
  final MyListing listing;

  const _SubmittedCard({required this.listing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: PropertyImage(
              seed: listing.draft.gradientSeed,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              decodeWidth: 58,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyStrong(color: Colors.white)
                      .copyWith(fontSize: 15.5, height: 20 / 15.5),
                ),
                const SizedBox(height: 3),
                Text(
                  listing.priceLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.amber,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(listing.status.badge,
                style: AppTextStyles.micro(color: Colors.white)
                    .copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// White / outlined pill for use on the teal field.
///
/// `PrimaryButton` and `GhostButton` both assume a light background — teal on
/// teal, and a white surface with a grey border, respectively. This is the one
/// screen with a coloured backdrop, so it gets its own pair rather than adding
/// an `onColor` variant to the shared buttons for a single caller.
class _LightButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _LightButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 56,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: filled
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.55)),
          ),
          child: Text(
            label,
            style: AppTextStyles.bodyStrong(
              color: filled ? AppColors.primary : Colors.white,
            ).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
