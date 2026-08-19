import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/property.dart';
import '../state/app_scope.dart';
import '../state/listings_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icons.dart';
import '../widgets/pill_button.dart';
import '../widgets/property_image.dart';
import '../widgets/state_views.dart';
import 'compare_screen.dart';

/// Screen 18 — the Home8 Fair Price explainer.
///
/// Reached from three places on the detail screen: the "Fair price" chip in the
/// price block, the gauge itself, and the "How is this calculated?" link. All
/// three land here because they're the same question.
///
/// The comparables are a repository call, not a prop — the detail screen holds
/// a `Property`, but the evidence behind the verdict is a separate resource
/// (`GET /listings/{id}/comparables`) and can be slow or empty independently of
/// the listing. So this sheet owns its own loading/error/empty branches.
class FairPriceSheet extends StatefulWidget {
  final Property property;

  const FairPriceSheet({super.key, required this.property});

  static Future<void> show(BuildContext context, Property property) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => FairPriceSheet(property: property),
    );
  }

  @override
  State<FairPriceSheet> createState() => _FairPriceSheetState();
}

class _FairPriceSheetState extends State<FairPriceSheet> {
  late final AsyncController<List<ComparableListing>> _comparables;

  /// Which comparable the user picked to put side-by-side. Null until they tap
  /// one; "Compare the Property" stays disabled while it is.
  ComparableListing? _selected;

  @override
  void initState() {
    super.initState();
    _comparables = AsyncController<List<ComparableListing>>(
      () => AppScope.repositoryOf(context).comparables(widget.property.id),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _comparables.load());
  }

  @override
  void dispose() {
    _comparables.dispose();
    super.dispose();
  }

  void _openCompare() {
    final other = _selected;
    if (other == null) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompareScreen(property: widget.property, other: other),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.property;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
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
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Home8 Fair Price',
                        style: AppTextStyles.h1().copyWith(fontSize: 22)),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          color: AppColors.ink, size: 24),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                children: [
                  FairPriceBandCard(property: p),
                  const SizedBox(height: 24),
                  Text('Select other Property to Compare',
                      style: AppTextStyles.h2().copyWith(fontSize: 17)),
                  const SizedBox(height: 12),
                  ListenableBuilder(
                    listenable: _comparables,
                    builder: (context, _) => _comparables.state.when(
                      loading: () => const _ComparableSkeletonList(),
                      error: (_) => ErrorStateView(
                        compact: true,
                        message: "Couldn't load comparable homes.",
                        onRetry: _comparables.load,
                      ),
                      data: (items) {
                        if (items.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              'No comparable homes have been recorded in '
                              '${p.area} yet.',
                              style: AppTextStyles.body(
                                  color: AppColors.inkMuted),
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final c in items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ComparableRow(
                                  comparable: c,
                                  selected: _selected?.id == c.id,
                                  onTap: () => setState(
                                    () => _selected =
                                        _selected?.id == c.id ? null : c,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CompareCta(
                    enabled: _selected != null,
                    onTap: _openCompare,
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

// ---------------------------------------------------------------------------
// Band card
// ---------------------------------------------------------------------------

/// The gauge plus the money labels and the verdict callout.
///
/// The detail screen renders a compact variant of this inline; the money-labelled
/// version lives here, where there's room for it.
class FairPriceBandCard extends StatelessWidget {
  final Property property;

  const FairPriceBandCard({super.key, required this.property});

  @override
  Widget build(BuildContext context) {
    final p = property;
    final fp = p.fairPrice;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F7),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FairPriceGauge(fairPrice: fp),
          const SizedBox(height: 12),
          _BandLabels(fairPrice: fp),
          const SizedBox(height: 16),
          _VerdictCallout(
            verdict: fp.verdict,
            text: fp.verdictSentence(p.currency, p.price),
          ),
        ],
      ),
    );
  }
}

/// Low → Fair → High gradient track with the marker at [FairPrice.position].
///
/// Public so the detail screen and the sheet share one implementation.
class FairPriceGauge extends StatelessWidget {
  final FairPrice fairPrice;
  const FairPriceGauge({super.key, required this.fairPrice});

  @override
  Widget build(BuildContext context) {
    final position = fairPrice.position.clamp(0.0, 1.0);

    return SizedBox(
      height: 30,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const marker = 30.0;
          final travel = constraints.maxWidth - marker;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  height: 9,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.primary,
                        Color(0xFF6FA84A),
                        AppColors.amber,
                        Color(0xFFE0553C),
                      ],
                      stops: [0, 0.42, 0.72, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: travel * position,
                top: 0,
                child: Container(
                  width: marker,
                  height: marker,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: AppColors.ink, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Low / FAIR BAND / High, with the money edges underneath when the backend
/// supplies them.
class _BandLabels extends StatelessWidget {
  final FairPrice fairPrice;
  const _BandLabels({required this.fairPrice});

  String _k(int value) {
    if (value >= 1000000) {
      final m = value / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 2)}M';
    }
    return '${(value / 1000).round()}k';
  }

  @override
  Widget build(BuildContext context) {
    final fp = fairPrice;
    final isFair = fp.verdict == PriceVerdict.fair;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _BandLabel(
            title: 'Low',
            value: fp.hasBands ? _k(fp.bandLow!) : null,
            align: TextAlign.start,
            highlight: fp.verdict == PriceVerdict.low,
            highlightColor: AppColors.primary,
          ),
        ),
        Expanded(
          child: _BandLabel(
            title: isFair ? 'FAIR BAND' : 'Fair',
            value: fp.hasBands ? '${_k(fp.fairLow!)} – ${_k(fp.fairHigh!)}' : null,
            align: TextAlign.center,
            highlight: isFair,
            highlightColor: AppColors.success,
          ),
        ),
        Expanded(
          child: _BandLabel(
            title: 'High',
            value: fp.hasBands ? _k(fp.bandHigh!) : null,
            align: TextAlign.end,
            highlight: fp.verdict == PriceVerdict.high,
            highlightColor: AppColors.danger,
          ),
        ),
      ],
    );
  }
}

class _BandLabel extends StatelessWidget {
  final String title;
  final String? value;
  final TextAlign align;
  final bool highlight;
  final Color highlightColor;

  const _BandLabel({
    required this.title,
    required this.value,
    required this.align,
    required this.highlight,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: switch (align) {
        TextAlign.start => CrossAxisAlignment.start,
        TextAlign.end => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.center,
      },
      children: [
        Text(
          title,
          textAlign: align,
          style: highlight
              ? AppTextStyles.micro(color: highlightColor)
                  .copyWith(fontSize: 12, fontWeight: FontWeight.w700)
              : AppTextStyles.caption(),
        ),
        if (value != null) ...[
          const SizedBox(height: 2),
          Text(
            value!,
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyStrong(color: AppColors.ink)
                .copyWith(fontSize: 14),
          ),
        ],
      ],
    );
  }
}

class _VerdictCallout extends StatelessWidget {
  final PriceVerdict verdict;
  final String text;

  const _VerdictCallout({required this.verdict, required this.text});

  @override
  Widget build(BuildContext context) {
    final (bg, dot) = switch (verdict) {
      PriceVerdict.low => (const Color(0xFFE7F4EC), AppColors.success),
      PriceVerdict.fair => (const Color(0xFFE7F4EC), AppColors.success),
      PriceVerdict.high => (const Color(0xFFFBEBE7), AppColors.danger),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body(color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Comparables
// ---------------------------------------------------------------------------

class _ComparableRow extends StatelessWidget {
  final ComparableListing comparable;
  final bool selected;
  final VoidCallback onTap;

  const _ComparableRow({
    required this.comparable,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = comparable;

    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTint : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: PropertyImage(
                seed: c.gradientSeed,
                url: c.photoUrl,
                decodeWidth: 58,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyStrong().copyWith(fontSize: 15.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatThousands(c.price),
              style: AppTextStyles.bodyStrong().copyWith(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparableSkeletonList extends StatelessWidget {
  const _ComparableSkeletonList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SkeletonBox(height: 80, radius: AppRadius.md),
          ),
      ],
    );
  }
}

/// Outlined row-style CTA matching the Figma, rather than the app's filled
/// primary button — this is a navigation affordance, not a commitment.
class _CompareCta extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _CompareCta({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? AppColors.ink : AppColors.inkMuted;

    return Pressable(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: enabled ? AppColors.ink : AppColors.line,
          ),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              AppIcons.compareArrows,
              width: 17,
              height: 17,
              colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                enabled ? 'Compare the Property' : 'Pick a home to compare',
                style: AppTextStyles.bodyStrong(color: fg).copyWith(
                  fontSize: 16,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: fg, size: 24),
          ],
        ),
      ),
    );
  }
}
