import 'package:flutter/material.dart';

import '../../models/listing_draft.dart';
import '../../state/post_listing_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/pill_button.dart';

/// Step 6 — "Reels Package" (prototype screen 44-1).
///
/// Two packages; the buttons ("Purchase the Package" / "Skip Reels") live in
/// the flow's footer. The choice is saved on the listing. Payments aren't
/// connected yet, so purchasing records the request and the team activates
/// it — the app says so plainly.
class StepReels extends StatelessWidget {
  final PostListingController controller;
  final ReelsPackage selected;
  final ValueChanged<ReelsPackage> onSelect;

  const StepReels({
    super.key,
    required this.controller,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Want people to see your property via reels?\n'
          'Reels can get people interest more quickly',
          style: AppTextStyles.body(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 26),
        _PopularCard(
          package: ReelsPackage.unlimited30d,
          selected: selected == ReelsPackage.unlimited30d,
          onTap: () => onSelect(ReelsPackage.unlimited30d),
        ),
        const SizedBox(height: 16),
        _CompactCard(
          package: ReelsPackage.century,
          selected: selected == ReelsPackage.century,
          onTap: () => onSelect(ReelsPackage.century),
        ),
        if (controller.draft.reelsPackage != null) ...[
          const SizedBox(height: 16),
          Text(
            'Requested: ${controller.draft.reelsPackage!.title}. '
            "We'll contact you to activate it.",
            style: AppTextStyles.caption(color: AppColors.success)
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

class _PopularCard extends StatelessWidget {
  final ReelsPackage package;
  final bool selected;
  final VoidCallback onTap;

  const _PopularCard({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg + 4),
              border: Border.all(
                color: selected ? AppColors.amber : AppColors.line,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.amber.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _IconSquare(
                      icon: Icons.bolt_rounded,
                      bg: Color(0xFFFCEBD2),
                      fg: AppColors.amber,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(package.title,
                              style: AppTextStyles.h2().copyWith(fontSize: 18)),
                          const SizedBox(height: 2),
                          Text(package.blurb, style: AppTextStyles.caption()),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Radio(selected: selected, color: AppColors.amber),
                  ],
                ),
                const SizedBox(height: 12),
                Text('AED ${package.priceAed}',
                    style: AppTextStyles.display().copyWith(fontSize: 30)),
              ],
            ),
          ),
          PositionedDirectional(
            end: 22,
            top: -12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('MOST POPULAR',
                  style: AppTextStyles.micro(color: Colors.white).copyWith(
                      fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactCard extends StatelessWidget {
  final ReelsPackage package;
  final bool selected;
  final VoidCallback onTap;

  const _CompactCard({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg + 4),
          border: Border.all(
            color: selected ? AppColors.amber : AppColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            const _IconSquare(
              icon: Icons.arrow_upward_rounded,
              bg: AppColors.primaryTint,
              fg: AppColors.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(package.title,
                      style: AppTextStyles.h2().copyWith(fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(package.blurb, style: AppTextStyles.caption()),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('AED ${package.priceAed}',
                style: AppTextStyles.h2().copyWith(fontSize: 18)),
            const SizedBox(width: 12),
            _Radio(selected: selected, color: AppColors.amber),
          ],
        ),
      ),
    );
  }
}

class _IconSquare extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;

  const _IconSquare({required this.icon, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, color: fg, size: 24),
    );
  }
}

class _Radio extends StatelessWidget {
  final bool selected;
  final Color color;

  const _Radio({required this.selected, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? color : Colors.transparent,
        border: Border.all(
          color: selected ? color : AppColors.line,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
          : null,
    );
  }
}
