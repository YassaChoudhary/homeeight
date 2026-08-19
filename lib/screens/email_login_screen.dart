import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../state/app_scope.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icons.dart';
import '../widgets/brand_mark.dart';
import '../widgets/pill_button.dart';
import 'otp_screen.dart';
import 'purpose_screen.dart';

/// Screen 24 — "Continue with Email".
///
/// Pushed from screen 23, so it gets a circular back button rather than the
/// tab layout. The alternate providers shown here are Phone and Google, not the
/// full set — you came from the phone screen, so offering Email again would be
/// circular.
class EmailLoginScreen extends StatefulWidget {
  final VoidCallback? onSignedIn;

  const EmailLoginScreen({super.key, this.onSignedIn});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final TextEditingController _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// Deliberately permissive: something before an @, something after, a dot in
  /// the domain. Anything stricter rejects valid addresses, and the real check
  /// is whether the code arrives.
  bool get _valid =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  Future<void> _continue() async {
    final auth = AppScope.authOf(context);
    await auth.requestEmailCode(_email.text.trim());
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpScreen(onSignedIn: widget.onSignedIn),
      ),
    );
  }

  Future<void> _google() async {
    final auth = AppScope.authOf(context);
    await auth.signInWithProvider(AuthMethod.google);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurposeScreen(onSignedIn: widget.onSignedIn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.authOf(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: auth,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding, 12, AppSpacing.screenPadding, 24),
            children: [
              const AuthBackButton(),
              const SizedBox(height: 20),
              Text('Continue with Email',
                  style: AppTextStyles.display().copyWith(fontSize: 27)),
              const SizedBox(height: 20),
              Container(
                height: 62,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.line),
                ),
                child: TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _valid ? _continue() : null,
                  style: AppTextStyles.bodyStrong().copyWith(fontSize: 16.5),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Email',
                    hintStyle: AppTextStyles.body(color: AppColors.inkMuted)
                        .copyWith(fontSize: 16.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Continue',
                loading: auth.busy,
                onTap: _valid ? _continue : null,
              ),
              const SizedBox(height: 22),
              const AuthOrDivider(),
              const SizedBox(height: 22),
              AuthProviderButton(
                label: 'Continue with Phone',
                iconAsset: AppIcons.authPhone,
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(height: 14),
              AuthProviderButton(
                label: 'Continue with Google',
                google: true,
                onTap: _google,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared auth chrome
// ---------------------------------------------------------------------------

/// Circular back button used on the pushed auth screens (24, 25).
class AuthBackButton extends StatelessWidget {
  const AuthBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line),
          ),
          child: const Icon(Icons.chevron_left_rounded,
              color: AppColors.ink, size: 26),
        ),
      ),
    );
  }
}

class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.line, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text('or', style: AppTextStyles.caption()),
        ),
        const Expanded(child: Divider(color: AppColors.line, height: 1)),
      ],
    );
  }
}

/// Outlined provider pill. Shared by screens 23 and 24 so they can't drift.
class AuthProviderButton extends StatelessWidget {
  final String label;
  final String? iconAsset;
  final bool google;
  final bool apple;
  final VoidCallback onTap;

  const AuthProviderButton({
    super.key,
    required this.label,
    required this.onTap,
    this.iconAsset,
    this.google = false,
    this.apple = false,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppTextStyles.bodyStrong().copyWith(fontSize: 16.5)),
            ),
            if (iconAsset != null)
              SvgPicture.asset(
                iconAsset!,
                width: 21,
                height: 21,
                colorFilter:
                    const ColorFilter.mode(AppColors.ink, BlendMode.srcIn),
              ),
            if (google) const BrandMark(BrandLogo.google),
            if (apple) const BrandMark(BrandLogo.apple),
          ],
        ),
      ),
    );
  }
}

