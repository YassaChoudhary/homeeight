import 'package:flutter/material.dart';

import '../../models/lister_profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home_nav_bar.dart';
import '../../widgets/pill_button.dart';
import '../main_shell.dart';
import 'my_listings_screen.dart';

/// "Verification submitted for review" — shown after the verification form,
/// in the same full-teal style as "Listing submitted for review".
///
/// "Go to my dashboard" resets to the app (Profile tab) and opens My
/// Listings, so Back never returns to the finished forms.
class VerificationSubmittedScreen extends StatelessWidget {
  final ListerProfile profile;

  const VerificationSubmittedScreen({super.key, required this.profile});

  static void goToDashboard(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const MainShell(initialTab: NavTab.profile),
      ),
      (route) => false,
    );
    navigator.push(
      MaterialPageRoute(builder: (_) => const MyListingsScreen()),
    );
  }

  String get _who => switch (profile.type) {
        ListerType.individual =>
          profile.legalName.isNotEmpty ? profile.legalName : 'Individual',
        _ => profile.organisation.isNotEmpty
            ? profile.organisation
            : profile.type.label,
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goToDashboard(context);
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
                    child: SingleChildScrollView(
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
                            'Verification submitted for review',
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
                                    text: "We're checking your documents. "
                                        'Most accounts are approved within '),
                                TextSpan(
                                  text: '1 business day',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                    text: '. You can follow the status in '
                                        'Verification center.'),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          // Summary card, like the listing one.
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.sm),
                                  ),
                                  child: Icon(
                                    profile.type == ListerType.individual
                                        ? Icons.person_outline_rounded
                                        : Icons.work_outline_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _who,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.bodyStrong(
                                                color: Colors.white)
                                            .copyWith(fontSize: 15.5),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${profile.type.label} account',
                                        style: AppTextStyles.caption(
                                            color: Colors.white70),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: AppColors.amber,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text('IN REVIEW',
                                      style: AppTextStyles.micro(
                                              color: Colors.white)
                                          .copyWith(
                                              fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 14),
                  child: Pressable(
                    onTap: () => goToDashboard(context),
                    child: Container(
                      height: 56,
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Go to my dashboard',
                        style: AppTextStyles.bodyStrong(
                                color: AppColors.primary)
                            .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
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
