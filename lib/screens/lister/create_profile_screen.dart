import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/lister_profile.dart';
import '../../state/app_scope.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/pill_button.dart';
import '../profile_screen.dart';
import 'verify_company_screen.dart';

/// Screen 28 — "Create your profile · How will you use Home8?".
///
/// The one screen that turns a browsing account into a listing account. Two
/// ways in:
///
/// 1. Screen 27 → "List a property" → Continue.
/// 2. Tapping `+` in the nav bar as someone who has never listed. The gate
///    signs them in, then routes here once before the post flow opens.
///
/// [onDone] is what makes the second path work: the caller decides where the
/// user lands, so the `+` path continues into the post flow instead of dumping
/// them on a profile screen. Same hold-the-intent rule as `SignInPrompt.gate`.
class CreateProfileScreen extends StatefulWidget {
  /// Run after the profile is saved, and after verification when the type needs
  /// it. Null means "close this screen and go back to wherever we came from".
  final VoidCallback? onDone;

  const CreateProfileScreen({super.key, this.onDone});

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  late final TextEditingController _name;
  ListerType _type = ListerType.individual;

  @override
  void initState() {
    super.initState();
    // Pre-filled from the session — the name is already known from sign-in, and
    // making someone retype it is friction for no gain.
    _name = TextEditingController(
      text: AppScope.authOf(context).user?.name ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _notYet(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$what is work in progress — coming soon.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navDark,
        ),
      );
  }

  void _continue() {
    final auth = AppScope.authOf(context);
    final name = _name.text.trim();
    if (name.isNotEmpty) auth.updateProfile(name: name);
    auth.setListerProfile(ListerProfile(type: _type));

    // Agents and companies verify the account before they get in; individuals
    // verify per listing at the permit step instead, so they go straight
    // through. See ListerType.needsAccountVerification.
    if (_type.needsAccountVerification) {
      // Chained to [_finish], not to widget.onDone directly. Verification pops
      // itself and calls this, which pops *this* screen and then runs the
      // caller's callback — so the post flow doesn't open on top of two
      // finished setup screens the back gesture would walk into.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyCompanyScreen(onDone: _finish),
        ),
      );
      return;
    }

    _finish();
  }

  void _finish() {
    final callback = widget.onDone;
    if (callback != null) {
      Navigator.of(context).pop();
      callback();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.authOf(context);

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
              child: ListenableBuilder(
                listenable: auth,
                builder: (context, _) {
                  final user = auth.user;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding, 8, AppSpacing.screenPadding, 20),
                    children: [
                      Text('Create your profile',
                          style: AppTextStyles.display().copyWith(fontSize: 28)),
                      const SizedBox(height: 8),
                      Text('How will you use Home8?',
                          style: AppTextStyles.body(color: AppColors.inkMuted)),
                      const SizedBox(height: 26),
                      Center(
                        child: Column(
                          children: [
                            // The dashed ring says "there's nothing here yet"
                            // without an empty-state label under an avatar that
                            // already has one.
                            _DashedAvatarRing(
                              child: user == null
                                  ? const SizedBox(width: 96, height: 96)
                                  : ProfileAvatar(
                                      user: user,
                                      size: 96,
                                      badge: _EditBadge(
                                        onTap: () => _notYet('Photo upload'),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 12),
                            Text.rich(
                              TextSpan(
                                style: AppTextStyles.body(),
                                children: [
                                  const TextSpan(text: 'Add a photo '),
                                  TextSpan(
                                    text: '(optional)',
                                    style: AppTextStyles.body(
                                        color: AppColors.inkMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      AppTextField(
                        controller: _name,
                        hint: 'Your full name',
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 18),
                      for (final type in ListerType.values) ...[
                        _TypeCard(
                          type: type,
                          selected: _type == type,
                          onTap: () => setState(() => _type = type),
                        ),
                        if (type != ListerType.values.last)
                          const SizedBox(height: 14),
                      ],
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding, 4, AppSpacing.screenPadding, 12),
              child: PrimaryButton(
                label: 'Continue',
                // A listing has to have a name against it, so this is the one
                // field that genuinely blocks.
                onTap: _name.text.trim().isEmpty ? null : _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Teal dashed ring around the avatar, matching the mock.
class _DashedAvatarRing extends StatelessWidget {
  final Widget child;
  const _DashedAvatarRing({required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      height: 116,
      child: CustomPaint(
        painter: const _DashedCirclePainter(),
        child: Center(child: child),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.width / 2 - 1,
      ));

    const dash = 8.0;
    const gap = 7.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EditBadge extends StatelessWidget {
  final VoidCallback onTap;
  const _EditBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.bg, width: 2.5),
        ),
        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 15),
      ),
    );
  }
}

/// One selectable account type. Same geometry as the purpose cards on screen
/// 27 so the two screens read as one flow; only the icon tint differs, which is
/// what distinguishes an agent from a company at a glance.
class _TypeCard extends StatelessWidget {
  final ListerType type;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  Color get _iconBg => switch (type) {
        ListerType.individual => AppColors.primaryTint,
        ListerType.agent => const Color(0xFFFCEBD2),
        ListerType.company => const Color(0xFFFBE0DC),
      };

  Color get _iconTint => switch (type) {
        ListerType.individual => AppColors.primary,
        ListerType.agent => AppColors.warning,
        ListerType.company => AppColors.danger,
      };

  IconData get _icon => switch (type) {
        ListerType.individual => Icons.person_outline_rounded,
        ListerType.agent => Icons.work_outline_rounded,
        ListerType.company => Icons.business_center_outlined,
      };

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
                color: _iconBg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              // The individual card reuses the "List a property" glyph from
              // screen 27, so the same idea keeps the same picture across the
              // two screens; the other two have no shipped SVG.
              child: type == ListerType.individual
                  ? Padding(
                      padding: const EdgeInsets.all(13),
                      child: SvgPicture.asset(
                        AppIcons.purposeList,
                        colorFilter:
                            ColorFilter.mode(_iconTint, BlendMode.srcIn),
                      ),
                    )
                  : Icon(_icon, color: _iconTint, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.label,
                      style:
                          AppTextStyles.bodyStrong().copyWith(fontSize: 16.5)),
                  const SizedBox(height: 2),
                  Text(type.blurb, style: AppTextStyles.caption()),
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
