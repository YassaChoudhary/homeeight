import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../state/app_scope.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icons.dart';
import '../widgets/home_nav_bar.dart';
import '../widgets/brand_mark.dart';
import '../widgets/pill_button.dart';
import 'email_login_screen.dart';
import 'otp_screen.dart';
import 'purpose_screen.dart';

/// Screen 23 — "Login or sign up to Home8".
///
/// This is the Login **tab**, not a pushed route, so it keeps the nav bar. When
/// a session exists `MainShell` shows `ProfileScreen` in this slot instead —
/// see `MainShell._buildTab`.
///
/// With Firebase on (Android): Email (next screen) and Google are real. Phone
/// OTP needs Firebase's paid Blaze plan and Apple needs an Apple Developer
/// account, so both explain that and point to Email/Google instead of faking a
/// sign-in. With Firebase off, every option uses the local stand-in.
class LoginScreen extends StatefulWidget {
  /// Present when the user was sent here by tapping a save heart. On success we
  /// return to the listing and apply the save, rather than dumping them on the
  /// profile screen having lost what they were doing.
  final VoidCallback? onSignedIn;

  /// Sheets pass true so the screen renders a close button instead of the tab
  /// layout.
  final bool asModal;

  const LoginScreen({super.key, this.onSignedIn, this.asModal = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phone = TextEditingController();
  DialCode _dial = DialCode.all.first;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  bool get _canContinue => _phone.text.replaceAll(RegExp(r'\D'), '').length >= 7;

  void _notAvailable(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _continueWithPhone() async {
    final auth = AppScope.authOf(context);
    if (auth.usesFirebase) {
      _notAvailable('Phone sign-in is coming soon. Please continue with '
          'Email or Google for now.');
      return;
    }
    await auth.requestPhoneCode(dial: _dial.dial, phone: _phone.text);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpScreen(onSignedIn: widget.onSignedIn),
      ),
    );
  }

  Future<void> _continueWithProvider(AuthMethod method) async {
    final auth = AppScope.authOf(context);
    if (auth.busy) return;

    if (auth.usesFirebase && method == AuthMethod.apple) {
      _notAvailable('Sign in with Apple is coming with the iOS app. Please '
          'continue with Email or Google for now.');
      return;
    }

    try {
      if (method == AuthMethod.google) {
        final signedIn = await auth.signInWithGoogle();
        if (!signedIn) return; // closed the Google picker
      } else {
        await auth.signInWithProvider(method);
      }
    } on AuthException catch (e) {
      if (mounted) _notAvailable(e.message);
      return;
    }
    if (!mounted) return;
    // New accounts get the intent question; returning users go straight in.
    continueAfterSignIn(context, widget.onSignedIn);
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<DialCode>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CountrySheet(selected: _dial),
    );
    if (picked != null && mounted) setState(() => _dial = picked);
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.authOf(context);

    return ColoredBox(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: auth,
          builder: (context, _) => ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              widget.asModal ? 8 : 26,
              AppSpacing.screenPadding,
              HomeNavBar.reservedSpace(context) + 20,
            ),
            children: [
              if (widget.asModal)
                Align(
                  alignment: AlignmentDirectional.topEnd,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded,
                          color: AppColors.ink, size: 24),
                    ),
                  ),
                ),
              Text(
                'Login or sign up to Home8',
                style: AppTextStyles.display().copyWith(fontSize: 27),
              ),
              const SizedBox(height: 22),
              _StackedField(
                dial: _dial,
                phoneController: _phone,
                onPickCountry: _pickCountry,
                onPhoneChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Text(
                "We'll call or text to confirm your number. Standard message "
                'and data rates apply.',
                style: AppTextStyles.caption().copyWith(fontSize: 13.5),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Continue',
                loading: auth.busy,
                onTap: _canContinue ? _continueWithPhone : null,
              ),
              const SizedBox(height: 22),
              const _OrDivider(),
              const SizedBox(height: 22),
              _ProviderButton(
                label: 'Continue with Email',
                iconAsset: AppIcons.authEmail,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EmailLoginScreen(onSignedIn: widget.onSignedIn),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _ProviderButton(
                label: 'Continue with Google',
                logo: _ProviderLogo.google,
                onTap: () => _continueWithProvider(AuthMethod.google),
              ),
              const SizedBox(height: 14),
              _ProviderButton(
                label: 'Continue with Apple',
                logo: _ProviderLogo.apple,
                onTap: () => _continueWithProvider(AuthMethod.apple),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Country row and phone row share one bordered container split by a dashed
/// rule, which is how the Figma draws it — not two separate fields.
class _StackedField extends StatelessWidget {
  final DialCode dial;
  final TextEditingController phoneController;
  final VoidCallback onPickCountry;
  final ValueChanged<String> onPhoneChanged;

  const _StackedField({
    required this.dial,
    required this.phoneController,
    required this.onPickCountry,
    required this.onPhoneChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPickCountry,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Country/Region',
                            style: AppTextStyles.caption().copyWith(fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          dial.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyStrong()
                              .copyWith(fontSize: 16.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.ink, size: 24),
                ],
              ),
            ),
          ),
          const _DashedRule(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Phone number',
                    style: AppTextStyles.caption().copyWith(fontSize: 13)),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  onChanged: onPhoneChanged,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                  ],
                  style: AppTextStyles.bodyStrong().copyWith(fontSize: 16.5),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.only(top: 2),
                    hintText: '50 123 4567',
                    hintStyle: AppTextStyles.bodyStrong(
                            color: AppColors.inkMuted)
                        .copyWith(fontSize: 16.5, fontWeight: FontWeight.w400),
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

class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        size: Size.infinite,
        painter: _DashedLinePainter(),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    const dash = 5.0, gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

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

enum _ProviderLogo { google, apple }

/// Outlined pill with the label left and the mark right, per the frames.
class _ProviderButton extends StatelessWidget {
  final String label;
  final String? iconAsset;
  final _ProviderLogo? logo;
  final VoidCallback onTap;

  const _ProviderButton({
    required this.label,
    required this.onTap,
    this.iconAsset,
    this.logo,
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
              child: Text(
                label,
                style: AppTextStyles.bodyStrong().copyWith(fontSize: 16.5),
              ),
            ),
            if (iconAsset != null)
              SvgPicture.asset(
                iconAsset!,
                width: 21,
                height: 21,
                colorFilter:
                    const ColorFilter.mode(AppColors.ink, BlendMode.srcIn),
              ),
            if (logo == _ProviderLogo.google)
              const BrandMark(BrandLogo.google),
            if (logo == _ProviderLogo.apple)
              const BrandMark(BrandLogo.apple),
          ],
        ),
      ),
    );
  }
}


/// Dial-code picker.
class _CountrySheet extends StatelessWidget {
  final DialCode selected;
  const _CountrySheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg + 8),
          topRight: Radius.circular(AppRadius.lg + 8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Country/Region',
                        style: AppTextStyles.h1().copyWith(fontSize: 21)),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.ink, size: 24),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: DialCode.all.length,
                itemBuilder: (context, i) {
                  final d = DialCode.all[i];
                  final active = d.country == selected.country;
                  return Pressable(
                    onTap: () => Navigator.of(context).pop(d),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primaryTint
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: Image.asset(d.flagAsset,
                                height: 20, cacheWidth: 90),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(d.country,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body()),
                          ),
                          Text(d.dial, style: AppTextStyles.bodyStrong()),
                          if (active) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check_rounded,
                                color: AppColors.primary, size: 20),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
