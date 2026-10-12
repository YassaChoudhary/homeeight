import 'package:flutter/material.dart';

import '../../models/listing_draft.dart';
import '../../models/lister_profile.dart';
import '../../state/app_scope.dart';
import '../../theme/app_colors.dart';
import '../post_listing/post_listing_flow.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/pill_button.dart';
import 'verification_center_screen.dart';
import 'verification_required_screen.dart';

/// What happens when a signed-in user taps + (or "Post another listing").
///
/// Only verified individuals, agents and companies can publish, so this asks
/// the server where the account stands first:
///
/// * **verified** → the post flow.
/// * **pending**  → a popup: "Account under verification".
/// * **none / rejected** → "Verification Required" (prototype 62) → the form
///   for their type → "Verification submitted for review".
///
/// Completes when the user is back where they started.
Future<void> startListing(BuildContext context, {ListingDraft? draft}) async {
  final auth = AppScope.authOf(context);
  final repo = AppScope.repositoryOf(context);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  // Small blocking spinner while we ask the server.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    ),
  );

  ListerProfile? server;
  Object? error;
  try {
    server = await repo.myVerification();
  } catch (e) {
    error = e;
  }
  navigator.pop(); // spinner

  if (error != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text("Couldn't check your account. Try again."),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navDark,
      ));
    return;
  }

  // Keep the app's copy of the status in step with the server.
  final cached = auth.user?.listerProfile;
  if (server != null) {
    auth.setListerProfile((cached ?? server).copyWith(
      type: server.type,
      status: server.status,
      reviewNote: server.reviewNote,
      legalName: server.legalName.isEmpty ? null : server.legalName,
      organisation: server.organisation.isEmpty ? null : server.organisation,
      licenceNumber: server.licenceNumber.isEmpty ? null : server.licenceNumber,
    ));
  }

  final status = server?.status ?? VerificationStatus.none;

  Future<void> openFlow() => navigator.push(
        MaterialPageRoute(
          builder: (_) => PostListingFlow(initialDraft: draft),
        ),
      );

  switch (status) {
    case VerificationStatus.verified:
      await openFlow();
    case VerificationStatus.pending:
      // Not approved yet: no posting, just say so.
      final viewStatus = await showDialog<bool>(
        context: navigator.context,
        builder: (_) => const _UnderVerificationDialog(),
      );
      if (viewStatus == true) {
        await navigator.push(
          MaterialPageRoute(builder: (_) => const VerificationCenterScreen()),
        );
      }
    case VerificationStatus.none:
    case VerificationStatus.rejected:
      // Verify first; after submitting they see "Verification submitted for
      // review" with "Go to my dashboard".
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => VerificationRequiredScreen(
            initialType: server?.type,
            rejectionNote:
                status == VerificationStatus.rejected ? server!.reviewNote : '',
          ),
        ),
      );
  }
}

/// "Account under verification" — shown on + while the account is pending.
class _UnderVerificationDialog extends StatelessWidget {
  const _UnderVerificationDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg + 4),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFFCEBD2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_top_rounded,
                  color: AppColors.amber, size: 30),
            ),
            const SizedBox(height: 18),
            Text('Account under verification',
                textAlign: TextAlign.center,
                style: AppTextStyles.h2().copyWith(fontSize: 20)),
            const SizedBox(height: 8),
            Text(
              "We're reviewing your documents. This usually takes up to 1 "
              "business day — you'll be able to post listings once your "
              'account is approved.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: AppColors.inkMuted)
                  .copyWith(fontSize: 14.5, height: 21 / 14.5),
            ),
            const SizedBox(height: 22),
            PrimaryButton(
              label: 'View status',
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 4),
            TertiaryButton(
              label: 'OK',
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
