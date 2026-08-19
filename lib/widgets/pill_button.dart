import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Press-scale wrapper. The app theme disables Material ink, so every tappable
/// surface takes its feedback from here instead.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.975,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Solid teal pill — the app's primary CTA (Continue, Allow location, Apply,
/// Show N Results, Save search…).
///
/// Full width by default, which is what every Figma screen shows. The previous
/// version returned a bare SizedBox with no width, so inside a
/// CrossAxisAlignment.start column it collapsed to the label's intrinsic width.
/// Pass `expand: false` only for inline CTAs that should hug their label
/// (the onboarding "Next" button).
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool expand;
  final bool loading;
  final bool glow;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.leadingIcon,
    this.trailingIcon,
    this.expand = true,
    this.loading = false,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;

    final content = Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: expand ? 24 : 30),
      decoration: BoxDecoration(
        color: enabled
            ? AppColors.primary
            : AppColors.primary.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
        boxShadow: enabled && glow
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyStrong(color: Colors.white)
                        .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 8),
                  Icon(trailingIcon, size: 18, color: Colors.white),
                ],
              ],
            ),
    );

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Pressable(onTap: enabled ? onTap : null, child: content),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Outlined pill on a white surface — secondary actions (Edit filters,
/// Show more).
class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? leadingIcon;
  final bool expand;

  const GhostButton({
    super.key,
    required this.label,
    required this.onTap,
    this.leadingIcon,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 18, color: AppColors.ink),
            const SizedBox(width: 8),
          ],
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
    );

    final button = Semantics(
      button: true,
      label: label,
      child: Pressable(onTap: onTap, child: content),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Bare text action — "Not now", "Skip", "Cancel".
class TertiaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const TertiaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            label,
            style: AppTextStyles.bodyStrong(color: color ?? AppColors.inkMuted)
                .copyWith(fontSize: 16),
          ),
        ),
      ),
    );
  }
}

/// Translucent outlined pill used over imagery — the Reels "Property details"
/// button and the "Skip" chip on onboarding.
class OverlayPillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool bordered;

  const OverlayPillButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.bordered = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(999),
            border: bordered
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 1.5,
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: AppTextStyles.bodyStrong(color: Colors.white)
                    .copyWith(fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.line,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
