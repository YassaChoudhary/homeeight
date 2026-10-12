import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/sign_in_prompt.dart';
import '../widgets/state_views.dart';
import 'lister/lister_gate.dart';

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

/// Signed in → `startListing` checks verification (only approved
/// individuals, agents and companies can publish) and routes accordingly.
void _openPostFlow(BuildContext context) {
  startListing(context);
}
