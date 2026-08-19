import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/sign_in_prompt.dart';
import '../widgets/state_views.dart';
import 'lister/create_profile_screen.dart';
import 'post_listing/post_listing_flow.dart';

/// Placeholder for flows that exist in the product but not yet in the app.
///
/// [message] is required rather than defaulted so each caller has to say what
/// specifically isn't built — a generic "coming soon" tells the user nothing and
/// tells the next developer even less about what's missing.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final String message;

  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(title, style: AppTextStyles.h2()),
        leading: BackButton(
          color: AppColors.ink,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Center(
        child: EmptyStateView(
          icon: Icons.hourglass_top_rounded,
          title: title,
          subtitle: message,
        ),
      ),
    );
  }
}

/// Opens the "post a listing" flow, behind a sign-in gate.
///
/// The raised centre `+` in the nav bar routes here from every surface that
/// shows the bar, so both the gate and the destination are defined once.
///
/// Listing requires an account for the same reason saving does — a property
/// has to belong to someone, and the seller has to be reachable about it. The
/// gate holds the intent, so a signed-out user who taps `+` lands in the post
/// flow straight after signing in rather than back where they started.
void openPostListingFlow(BuildContext context) {
  SignInPrompt.gateListing(
    context,
    action: () => _openPostFlow(context),
  );
}

/// ## Why there can be a screen before the stepper
///
/// The permit step needs to know whether this is an owner posting their own
/// home or an agency posting a client's — the required document differs, and so
/// does the badge. So a signed-in user who has never listed passes through
/// screen 28 once, and only once; after that `listerProfile` exists and `+`
/// goes straight to the form.
///
/// `onDone` is what keeps this from being a detour: screen 28 (and screen 29
/// behind it, for agencies) hands control back here rather than dropping the
/// user on a profile screen, so the `+` they pressed still ends in the form
/// they wanted.
void _openPostFlow(BuildContext context) {
  final user = AppScope.authOf(context).user;

  if (user != null && user.listerProfile == null) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateProfileScreen(
          onDone: () => _pushFlow(context),
        ),
      ),
    );
    return;
  }

  _pushFlow(context);
}

void _pushFlow(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const PostListingFlow()),
  );
}
