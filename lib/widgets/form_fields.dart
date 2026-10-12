import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'pill_button.dart';

/// Form primitives shared by the lister screens and the post-a-listing flow.
///
/// These were private classes inside `filters_sheet.dart` and
/// `edit_profile_screen.dart` before the seller side existed. Seven new screens
/// need the same boxed field, the same choice pill and the same tinted note, so
/// they live here rather than being copied an eighth time.
///
/// Nothing in this file hardcodes a colour, size or radius — everything comes
/// from `theme/`.

// ---------------------------------------------------------------------------
// Labels and text fields
// ---------------------------------------------------------------------------

/// Bold label above a field — "Company name", "Yearly rent".
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTextStyles.bodyStrong().copyWith(fontSize: 15.5),
      );
}

/// White boxed input with a rounded border.
///
/// [focusTint] draws the teal border and glow the design shows on the active
/// field. It's driven by a real [FocusNode] rather than a bool the caller has
/// to remember to set, so the highlight can't get stuck on the wrong field.
class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final int? minLines;
  final int? maxLength;

  /// Sits inside the box on the trailing edge — the "sqft ▾" unit picker, the
  /// "Map" link, a search glyph.
  final Widget? trailing;

  /// Leading glyph inside the box.
  final IconData? icon;

  /// Leading widget (e.g. a flag) — used instead of [icon] when set.
  final Widget? leading;

  /// Fully rounded ends, as on the post-listing screens. Multi-line fields
  /// keep the card radius.
  final bool pill;

  final TextCapitalization textCapitalization;

  const AppTextField({
    super.key,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.formatters,
    this.onChanged,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.trailing,
    this.icon,
    this.leading,
    this.pill = false,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);
  bool _focused = false;

  void _onFocus() {
    if (_focused != _focus.hasFocus) setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsetsDirectional.only(start: 18, end: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(
            widget.pill && widget.maxLines == 1 ? 999 : AppRadius.md),
        border: Border.all(
          color: _focused ? AppColors.primary : AppColors.line,
          width: _focused ? 1.8 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: widget.maxLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 12),
          ] else if (widget.icon != null) ...[
            Padding(
              padding: EdgeInsets.only(top: widget.maxLines > 1 ? 20 : 0),
              child: Icon(widget.icon, size: 20, color: AppColors.inkMuted),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                  vertical: widget.maxLines > 1 ? 16 : 0),
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                keyboardType: widget.keyboardType,
                inputFormatters: widget.formatters,
                onChanged: widget.onChanged,
                maxLines: widget.maxLines,
                minLines: widget.minLines,
                maxLength: widget.maxLength,
                textCapitalization: widget.textCapitalization,
                style: AppTextStyles.bodyStrong().copyWith(fontSize: 16.5),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  // The built-in counter is grey text inside the box; the
                  // design puts "48 / 70" outside it, so CharCount does that.
                  counterText: '',
                  hintText: widget.hint,
                  hintStyle: AppTextStyles.body(color: AppColors.inkMuted)
                      .copyWith(fontSize: 16.5),
                ),
              ),
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 8),
            Padding(
              padding: EdgeInsets.only(top: widget.maxLines > 1 ? 18 : 0),
              child: widget.trailing!,
            ),
          ],
        ],
      ),
    );
  }
}

/// "48 / 70" under a length-capped field, right-aligned.
class CharCount extends StatelessWidget {
  final int length;
  final int max;
  const CharCount({super.key, required this.length, required this.max});

  @override
  Widget build(BuildContext context) {
    final over = length > max;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Text(
        '$length / $max',
        style: AppTextStyles.micro(
          color: over ? AppColors.danger : AppColors.inkMuted,
        ).copyWith(fontSize: 11.5, fontWeight: FontWeight.w400),
      ),
    );
  }
}

/// Compact inline picker used inside a field box — "sqft ▾", "AED / year ▾".
///
/// Deliberately not a `DropdownButton`: at this size the Material dropdown's
/// own padding and underline fight the field box around it.
class InlineUnitPicker<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  const InlineUnitPicker({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    final choice = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(),
              const SizedBox(height: 6),
              for (final option in options)
                Pressable(
                  onTap: () => Navigator.of(sheetContext).pop(option),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(labelOf(option),
                              style: AppTextStyles.bodyStrong()
                                  .copyWith(fontSize: 16.5)),
                        ),
                        if (option == value)
                          const Icon(Icons.check_rounded,
                              color: AppColors.primary, size: 20),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choice != null) onChanged(choice);
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => _pick(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(labelOf(value),
                style: AppTextStyles.bodyStrong(color: AppColors.inkMuted)),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// Full-width dropdown in a rounded box — the country and city pickers on the
/// location step. Shows an optional leading widget, e.g. a flag.
class AppSelectField<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T value) labelOf;
  final Widget Function(T value)? leadingOf;
  final ValueChanged<T> onChanged;

  const AppSelectField({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.leadingOf,
  });

  Future<void> _pick(BuildContext context) async {
    final choice = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(),
              const SizedBox(height: 6),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final option = options[i];
                    return Pressable(
                      onTap: () => Navigator.of(sheetContext).pop(option),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 15),
                        child: Row(
                          children: [
                            if (leadingOf != null) ...[
                              leadingOf!(option),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Text(labelOf(option),
                                  style: AppTextStyles.bodyStrong()
                                      .copyWith(fontSize: 16.5)),
                            ),
                            if (option == value)
                              const Icon(Icons.check_rounded,
                                  color: AppColors.primary, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choice != null) onChanged(choice);
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => _pick(context),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            if (leadingOf != null) ...[
              leadingOf!(value),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                labelOf(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyStrong().copyWith(fontSize: 16),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Counters, pills, segments
// ---------------------------------------------------------------------------

/// "− 2 +" stepper for bedrooms and bathrooms.
///
/// The decrement button greys out at [min] rather than disappearing, so the
/// control doesn't change width as you use it.
class CounterField extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const CounterField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          _Round(
            icon: Icons.remove_rounded,
            enabled: value > min,
            filled: false,
            onTap: () => onChanged(value - 1),
          ),
          Expanded(
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyStrong().copyWith(fontSize: 17),
            ),
          ),
          _Round(
            icon: Icons.add_rounded,
            enabled: value < max,
            filled: true,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _Round extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final bool filled;
  final VoidCallback onTap;

  const _Round({
    required this.icon,
    required this.enabled,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? (enabled ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35))
        : const Color(0xFFEFF2F3);
    final fg = filled
        ? Colors.white
        : (enabled ? AppColors.ink : AppColors.inkMuted);

    return Pressable(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: fg),
      ),
    );
  }
}

/// Rounded choice pill — Furnished / Unfurnished / Partly.
class ChoicePill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const ChoicePill({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surface,
          border: Border.all(color: active ? AppColors.primary : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodyStrong(
              color: active ? Colors.white : AppColors.ink),
        ),
      ),
    );
  }
}

/// Two-up segmented control on a grey track with a white active pill — the
/// For Rent / For Sale toggle on the basics step, and the range tabs on the
/// performance screen.
class SegmentedControl<T> extends StatelessWidget {
  final List<T> options;
  final T value;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;
  final double height;

  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEEF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(option),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option == value
                        ? AppColors.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: option == value
                        ? [
                            BoxShadow(
                              color: AppColors.ink.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labelOf(option),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyStrong(
                      color: option == value
                          ? AppColors.ink
                          : AppColors.inkMuted,
                    ).copyWith(fontSize: 15.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notes, uploads, dashed tiles
// ---------------------------------------------------------------------------

/// The tone of an [InfoNote]. Each maps to an existing token pair — no new
/// colours are introduced here.
enum NoteTone { info, warning, success }

/// Tinted callout with a leading glyph — "A trade licence will be required at
/// the verification step", "Photos are auto-checked", "Within the fair band".
class InfoNote extends StatelessWidget {
  final String message;
  final NoteTone tone;
  final IconData? icon;

  /// Optional bold action on the trailing edge, e.g. "Try again".
  final String? actionLabel;
  final VoidCallback? onAction;

  const InfoNote({
    super.key,
    required this.message,
    this.tone = NoteTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  Color get _bg => switch (tone) {
        NoteTone.info => AppColors.primaryTint,
        NoteTone.warning => const Color(0xFFFCEBD2),
        NoteTone.success => const Color(0xFFE7F4EC),
      };

  Color get _fg => switch (tone) {
        NoteTone.info => AppColors.primary,
        NoteTone.warning => AppColors.warning,
        NoteTone.success => AppColors.success,
      };

  IconData get _icon =>
      icon ??
      switch (tone) {
        NoteTone.info => Icons.info_outline_rounded,
        NoteTone.warning => Icons.schedule_rounded,
        NoteTone.success => Icons.circle,
      };

  @override
  Widget build(BuildContext context) {
    final isDot = tone == NoteTone.success && icon == null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Nudged down so the glyph sits on the first line's baseline
            // rather than its cap height.
            padding: EdgeInsets.only(top: isDot ? 7 : 1),
            child: Icon(_icon, size: isDot ? 8 : 17, color: _fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption(color: _fg)
                  .copyWith(fontSize: 13.5, height: 19 / 13.5),
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: AppTextStyles.bodyStrong(color: _fg)
                    .copyWith(fontSize: 13.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A file that has been attached — icon, name, "Uploaded · 1.2 MB", and a
/// trailing action.
class UploadedRow extends StatelessWidget {
  final String fileName;
  final String statusLine;
  final IconData icon;

  /// "Replace" when the file is optional to change, a tick when it's just done.
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showTick;

  const UploadedRow({
    super.key,
    required this.fileName,
    required this.statusLine,
    this.icon = Icons.description_outlined,
    this.actionLabel,
    this.onAction,
    this.showTick = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFE7F4EC),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 22, color: AppColors.success),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyStrong().copyWith(fontSize: 15.5),
                ),
                const SizedBox(height: 2),
                Text(
                  statusLine,
                  style: AppTextStyles.caption(color: AppColors.success)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (showTick)
            const Icon(Icons.check_rounded, color: AppColors.success, size: 22)
          else if (actionLabel != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  actionLabel!,
                  style: AppTextStyles.bodyStrong(color: AppColors.inkMuted)
                      .copyWith(decoration: TextDecoration.underline),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dashed-outline tile for "+ Add broker card", "Add photos", "Add video".
class DashedAddTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final Color tintBg;
  final double height;

  /// Lays the glyph and label side by side instead of stacked. Used for the
  /// single-line "+ Add broker card (optional)" row.
  final bool inline;

  final VoidCallback? onTap;

  const DashedAddTile({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.add_rounded,
    this.tint = AppColors.primary,
    this.tintBg = AppColors.primaryTint,
    this.height = 64,
    this.inline = true,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: CustomPaint(
        painter: const DashedBorderPainter(),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: inline
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 19, color: AppColors.inkMuted),
                    const SizedBox(width: 10),
                    Text(label,
                        style: AppTextStyles.body(color: AppColors.inkMuted)
                            .copyWith(fontSize: 15.5)),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration:
                          BoxDecoration(color: tintBg, shape: BoxShape.circle),
                      child: Icon(icon, size: 20, color: tint),
                    ),
                    const SizedBox(height: 10),
                    Text(label,
                        style: AppTextStyles.bodyStrong(color: tint)
                            .copyWith(fontSize: 14.5)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Dashed rounded-rect border.
///
/// Same walk-the-path technique as the one in `gallery_screen.dart`; this one
/// is public and takes a colour so the light surfaces here and the dark overlay
/// there don't need two painters.
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const DashedBorderPainter({
    this.color = AppColors.line,
    this.radius = AppRadius.md,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));

    const dash = 7.0;
    const gap = 6.0;
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
  bool shouldRepaint(covariant DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

/// Small pill showing a delta — "▲ 18%", "▼ 2%".
///
/// Green for up, muted red for down. A change of exactly zero renders neutral
/// rather than green, because "▲ 0%" is a lie in a green box.
class TrendPill extends StatelessWidget {
  final double? changePct;
  final String? suffix;
  final bool compact;

  const TrendPill({
    super.key,
    required this.changePct,
    this.suffix,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final value = changePct;
    if (value == null) return const SizedBox.shrink();

    final up = value > 0;
    final flat = value == 0;
    final fg = flat
        ? AppColors.inkMuted
        : up
            ? AppColors.success
            : AppColors.danger;

    final magnitude = value.abs();
    final text = magnitude % 1 == 0
        ? magnitude.toStringAsFixed(0)
        : magnitude.toStringAsFixed(1);

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!flat)
          Icon(up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
              size: 18, color: fg),
        Text(
          '$text%${suffix == null ? '' : ' $suffix'}',
          style: AppTextStyles.micro(color: fg)
              .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ],
    );

    if (compact) return row;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: flat
            ? const Color(0xFFEFF2F3)
            : up
                ? const Color(0xFFE7F4EC)
                : const Color(0xFFFAE9E6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: row,
    );
  }
}

/// Digits-only input that strips thousands separators as the user types, so
/// "96,000" and "96000" both parse.
class ThousandsFormatter extends TextInputFormatter {
  const ThousandsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final formatted = group(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Groups a digit string into thousands. Public so screens can seed a
  /// controller with an already-formatted value without reimplementing it.
  static String group(String digits) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final fromEnd = digits.length - i;
      buf.write(digits[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  /// Parses a grouped string back to an int. Returns null for empty input, so
  /// "cleared the field" stays distinguishable from "typed zero".
  static int? parse(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }
}
