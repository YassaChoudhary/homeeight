import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../state/app_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'brand_mark.dart';
import 'home_nav_bar.dart';
import 'pill_button.dart';
import '../screens/login_screen.dart';

/// Prompt shown when an anonymous user taps a save heart.
///
/// ## Hold-and-apply
///
/// The tap that triggered this is **not** discarded. [SignInPrompt.gate] returns
/// a callback that the caller runs after a successful sign-in, so the listing
/// the user was reaching for gets saved without them having to find it again.
/// Dropping the intent and dumping them on a profile screen is the behaviour
/// that makes people give up on signing in.
///
/// Everything here is frontend-only — the session is local and any six-digit
/// code is accepted. See `AuthController`.
class SignInPrompt {
  SignInPrompt._();

  /// Runs [action] if signed in; otherwise prompts, then runs it on success.
  ///
  /// Call this instead of touching `SavedListingsStore` directly from any new
  /// save affordance, so the gate can't be forgotten in one place.
  static Future<void> gate(
    BuildContext context, {
    required VoidCallback action,
    String title = 'Sign in to save homes',
    String message = 'Create a free account to save favourites, get '
        'price-drop alerts and chat with agents.',
    String icon = NavIcons.heart,
  }) async {
    final auth = AppScope.authOf(context);
    if (auth.isSignedIn) {
      action();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (sheetContext) => _SignInSheet(
        title: title,
        message: message,
        icon: icon,
        onSignedIn: action,
      ),
    );
  }

  /// The listing variant, shown when a signed-out user taps the `+`.
  ///
  /// Same sheet, different words and glyph — posting a property is a bigger
  /// commitment than saving one, so the copy names it plainly rather than
  /// reusing the save wording.
  static Future<void> gateListing(
    BuildContext context, {
    required VoidCallback action,
  }) {
    return gate(
      context,
      action: action,
      title: 'Sign in to list Property',
      message: 'Create a free account to list a property, continue to rent '
          'out or sell.',
      icon: NavIcons.post,
    );
  }
}

class _SignInSheet extends StatelessWidget {
  final String title;
  final String message;
  final String icon;
  final VoidCallback onSignedIn;

  const _SignInSheet({
    required this.title,
    required this.message,
    required this.icon,
    required this.onSignedIn,
  });

  void _openLogin(BuildContext context) {
    // Close the prompt first so the auth stack isn't sitting on top of a sheet
    // that would still be there when it unwinds.
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.bg,
          body: LoginScreen(asModal: true, onSignedIn: onSignedIn),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg + 8),
          topRight: Radius.circular(AppRadius.lg + 8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(),
              const SizedBox(height: 22),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(26),
                ),
                padding: const EdgeInsets.all(22),
                child: SvgPicture.asset(
                  icon,
                  colorFilter: const ColorFilter.mode(
                      AppColors.primary, BlendMode.srcIn),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.display().copyWith(fontSize: 24),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.body(color: AppColors.inkMuted),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Continue with Phone',
                onTap: () => _openLogin(context),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SocialButton(
                      label: 'Google',
                      logo: BrandLogo.google,
                      onTap: () => _openLogin(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SocialButton(
                      label: 'Apple',
                      logo: BrandLogo.apple,
                      onTap: () => _openLogin(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text.rich(
                    TextSpan(
                      style: AppTextStyles.body(color: AppColors.inkMuted),
                      children: [
                        const TextSpan(text: 'Not now, '),
                        TextSpan(
                          text: 'keep browsing',
                          style: AppTextStyles.bodyStrong(color: AppColors.ink)
                              .copyWith(
                                  decoration: TextDecoration.underline),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Google / Apple button. Both route to the same login screen for now — the
/// OAuth providers aren't wired up yet, and a dead button would be worse than
/// one that gets you somewhere useful.
/// Google / Apple button on the save-gate sheet.
///
/// Both route to the login screen for now — the OAuth SDKs aren't wired up, and
/// a dead button is worse than one that gets you somewhere useful.
///
/// Logo sits left of a centred label, matching the design. Uses [BrandMark] so
/// the artwork is identical to the login screens.
class _SocialButton extends StatelessWidget {
  final String label;
  final BrandLogo logo;
  final VoidCallback onTap;

  const _SocialButton({
    required this.label,
    required this.logo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BrandMark(logo, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyStrong().copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
