import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../state/app_scope.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icons.dart';
import '../widgets/home_nav_bar.dart';
import '../widgets/pill_button.dart';
import 'lister/create_profile_screen.dart';
import 'main_shell.dart';

/// Screen 27 — "What brings you to Home8?", the last step of the auth flow.
///
/// ## Both options now proceed
///
/// **List a property** used to show a work-in-progress snackbar, because there
/// was nowhere to send someone who chose it. There is now: it continues to
/// screen 28 (`CreateProfileScreen`), and from there to company verification
/// for an agency, or straight into the app for an individual.
///
/// The buyer path is unchanged — Continue goes to the shell on Discover.
class PurposeScreen extends StatefulWidget {
  /// Set when the flow was entered from a save tap. Called instead of pushing
  /// the shell, so the user lands back on the listing they were looking at.
  final VoidCallback? onSignedIn;

  const PurposeScreen({super.key, this.onSignedIn});

  @override
  State<PurposeScreen> createState() => _PurposeScreenState();
}

class _PurposeScreenState extends State<PurposeScreen> {
  UserIntent _selected = UserIntent.findProperty;

  void _select(UserIntent intent) {
    setState(() => _selected = intent);
  }

  void _finish() {
    AppScope.authOf(context).setIntent(_selected);

    // The lister path needs one more question before the app is useful to
    // them — individual, agent or agency — because the verification document
    // and the badge both depend on the answer. Screen 28 asks it, then calls
    // back here to land them in the app.
    if (_selected == UserIntent.listProperty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CreateProfileScreen(onDone: _land),
        ),
      );
      return;
    }

    _land();
  }

  /// Where every path out of this screen ends up.
  ///
  /// Kept in one place so the save-tap callback and the two intents can't drift
  /// into three different ideas of "done".
  void _land() {
    final callback = widget.onSignedIn;
    if (callback != null) {
      // Came from a save tap: unwind the auth stack and let the caller resume.
      Navigator.of(context).popUntil((route) => route.isFirst);
      callback();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const MainShell(initialTab: NavTab.discover),
      ),
      (route) => false,
    );
  }

  /// "Just browsing? Skip for now" — keeps the session but leaves the intent at
  /// its default rather than recording a choice the user didn't make.
  void _skip() => _land();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Icon(Icons.arrow_back_rounded,
                      color: AppColors.ink, size: 24),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding, 8, AppSpacing.screenPadding, 20),
                children: [
                  Text('What brings you to Home8?',
                      style: AppTextStyles.display().copyWith(fontSize: 28)),
                  const SizedBox(height: 10),
                  Text(
                    'Pick one to get started, you can change this later in '
                    'profile',
                    style: AppTextStyles.body(color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 22),
                  _PurposeCard(
                    icon: AppIcons.purposeFind,
                    title: 'Find a Property',
                    subtitle: 'Buy, rent or book a short stay',
                    selected: _selected == UserIntent.findProperty,
                    onTap: () => _select(UserIntent.findProperty),
                  ),
                  const SizedBox(height: 14),
                  _PurposeCard(
                    icon: AppIcons.purposeList,
                    title: 'List a property',
                    subtitle: 'Rent out or sell - owner, agent or company',
                    selected: _selected == UserIntent.listProperty,
                    onTap: () => _select(UserIntent.listProperty),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 10),
              child: Column(
                children: [
                  PrimaryButton(label: 'Continue', onTap: _finish),
                  const SizedBox(height: 12),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _skip,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Just browsing? Skip for now',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body(color: AppColors.inkMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurposeCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PurposeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.line,
            width: selected ? 1.8 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              padding: const EdgeInsets.all(12),
              child: SvgPicture.asset(
                icon,
                colorFilter:
                    const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          AppTextStyles.bodyStrong().copyWith(fontSize: 16.5)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.caption()),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Radio(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  final bool selected;
  const _Radio({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.line,
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
          : null,
    );
  }
}
