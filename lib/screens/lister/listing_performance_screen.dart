import 'package:flutter/material.dart';

import '../../models/my_listing.dart';
import '../../models/property.dart';
import '../../state/app_scope.dart';
import '../../state/listings_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/property_image.dart';
import '../../widgets/state_views.dart';

/// Screen 32 — "Performance" for one listing.
///
/// Reached from the ⋮ menu on My Listings. Everything on it is one repository
/// call per range, so switching 30 days / 7 days / 24 h refetches rather than
/// slicing a cached series — the backend computes the comparison against the
/// previous window, and that can't be derived client-side from a 30-day array.
class ListingPerformanceScreen extends StatefulWidget {
  final MyListing listing;

  const ListingPerformanceScreen({super.key, required this.listing});

  @override
  State<ListingPerformanceScreen> createState() =>
      _ListingPerformanceScreenState();
}

class _ListingPerformanceScreenState extends State<ListingPerformanceScreen> {
  PerformanceRange _range = PerformanceRange.days30;
  late final AsyncController<ListingPerformance> _performance;
  bool _boosting = false;

  @override
  void initState() {
    super.initState();
    _performance = AsyncController<ListingPerformance>(
      () => AppScope.repositoryOf(context)
          .listingPerformance(widget.listing.id, range: _range),
    )..load();
  }

  @override
  void dispose() {
    _performance.dispose();
    super.dispose();
  }

  void _setRange(PerformanceRange range) {
    if (_range == range) return;
    setState(() => _range = range);
    // AsyncController cancels stale responses by request id, so a fast
    // double-tap between tabs can't land the wrong window's numbers.
    _performance.load();
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

  Future<void> _boost() async {
    setState(() => _boosting = true);
    try {
      await AppScope.repositoryOf(context).boostListing(widget.listing.id);
      if (!mounted) return;
      _performance.load();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Boost applied — featured placement is live.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.navDark,
          ),
        );
    } catch (_) {
      if (mounted) _notYet('Boosting');
    } finally {
      if (mounted) setState(() => _boosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back_rounded,
                          color: AppColors.ink, size: 24),
                    ),
                  ),
                  Expanded(
                    child: Text('Performance',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.h1().copyWith(fontSize: 21)),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _notYet('Exporting a report'),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.ios_share_rounded,
                          color: AppColors.ink, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding, 4, AppSpacing.screenPadding, 28),
                children: [
                  _ListingSelector(listing: widget.listing),
                  const SizedBox(height: 16),
                  SegmentedControl<PerformanceRange>(
                    options: PerformanceRange.values,
                    value: _range,
                    labelOf: (r) => r.label,
                    onChanged: _setRange,
                  ),
                  const SizedBox(height: 16),
                  ListenableBuilder(
                    listenable: _performance,
                    builder: (context, _) => _performance.state.when(
                      loading: () => const _PerformanceSkeleton(),
                      error: (_) => ErrorStateView(
                        message: "We couldn't load these numbers.",
                        onRetry: _performance.load,
                      ),
                      data: (data) => Column(
                        children: [
                          _ViewsCard(data: data),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _MetricCard(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  tint: AppColors.primary,
                                  label: 'Enquiries',
                                  value: '${data.enquiries}',
                                  footnote: data.totalViews == 0
                                      ? null
                                      : '${data.conversionPct.toStringAsFixed(1)}'
                                          '% conversion',
                                  footnoteColor: AppColors.success,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _MetricCard(
                                  icon: Icons.favorite_border_rounded,
                                  tint: AppColors.amber,
                                  label: 'Saves',
                                  value: '${data.saves}',
                                  footnote: data.savesRank.isEmpty
                                      ? null
                                      : data.savesRank,
                                ),
                              ),
                            ],
                          ),
                          if (data.boostPrice.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _BoostBanner(
                              price: data.boostPrice,
                              busy: _boosting,
                              onTap: _boost,
                            ),
                          ],
                        ],
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

/// The listing this screen is about, at the top so there's never doubt.
///
/// The chevron is inert for now — switching listings from here needs a picker
/// that lists them all, which is what My Listings already is. Kept visible
/// because the design shows it and it's one screen away from being real.
class _ListingSelector extends StatelessWidget {
  final MyListing listing;

  const _ListingSelector({required this.listing});

  @override
  Widget build(BuildContext context) {
    final expiry = listing.expiresInDays;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: PropertyImage(
              seed: listing.draft.gradientSeed,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              decodeWidth: 54,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyStrong().copyWith(fontSize: 16),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    listing.status.label,
                    if (expiry != null) '$expiry days remaining',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(),
                ),
              ],
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.inkMuted),
        ],
      ),
    );
  }
}

/// Total views, the delta pill, and the area chart.
class _ViewsCard extends StatelessWidget {
  final ListingPerformance data;

  const _ViewsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total views', style: AppTextStyles.caption()),
                    const SizedBox(height: 4),
                    Text(formatThousands(data.totalViews),
                        style:
                            AppTextStyles.display().copyWith(fontSize: 30)),
                  ],
                ),
              ),
              TrendPill(changePct: data.viewsChangePct, suffix: 'vs prev.'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _AreaChartPainter(
                  values: [for (final p in data.series) p.value],
                  peak: data.peak,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final point in data.series)
                Flexible(
                  child: Text(
                    point.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.micro()
                        .copyWith(fontSize: 11, fontWeight: FontWeight.w400),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Smoothed area chart.
///
/// A `CustomPainter` rather than a chart package: this is one series with no
/// axes, no legend and no interaction, and `fl_chart` would add a dependency
/// (and a pub get he'd have to run) for about sixty lines of drawing. The same
/// reasoning as the fair-price gauge and the map grid already in the app.
///
/// Points are joined with cubic segments whose control points sit on the
/// midpoint x — the standard trick for a curve that never overshoots above the
/// peak, which matters when the peak is a real number someone is reading.
class _AreaChartPainter extends CustomPainter {
  final List<int> values;
  final int peak;

  const _AreaChartPainter({required this.values, required this.peak});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    // Leave headroom so the top of the curve isn't clipped by the box.
    const topPad = 10.0;
    final usableHeight = size.height - topPad;
    final stepX = size.width / (values.length - 1);

    Offset pointAt(int i) => Offset(
          i * stepX,
          topPad + usableHeight * (1 - values[i] / peak),
        );

    final line = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 0; i < values.length - 1; i++) {
      final current = pointAt(i);
      final next = pointAt(i + 1);
      final midX = (current.dx + next.dx) / 2;
      line.cubicTo(midX, current.dy, midX, next.dy, next.dx, next.dy);
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.primary.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Dot on the latest point — the value the reader cares about most.
    final last = pointAt(values.length - 1);
    canvas.drawCircle(last, 4.5, Paint()..color = AppColors.primary);
    canvas.drawCircle(
      last,
      4.5,
      Paint()
        ..color = AppColors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _AreaChartPainter old) =>
      old.peak != peak || !identical(old.values, values);
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final String? footnote;
  final Color? footnoteColor;

  const _MetricCard({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    this.footnote,
    this.footnoteColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: AppTextStyles.display().copyWith(fontSize: 26)),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Text(
              footnote!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption(
                color: footnoteColor ?? AppColors.inkMuted,
              ).copyWith(fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// The dark boost upsell at the bottom.
class _BoostBanner extends StatelessWidget {
  final String price;
  final bool busy;
  final VoidCallback onTap;

  const _BoostBanner({
    required this.price,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navDark,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.bolt_rounded,
                size: 24, color: AppColors.amber),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Boost this listing',
                    style: AppTextStyles.bodyStrong(color: Colors.white)
                        .copyWith(fontSize: 16)),
                const SizedBox(height: 2),
                Text('Featured placement · ~4× more views',
                    style: AppTextStyles.caption(color: Colors.white60)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Pressable(
            onTap: busy ? null : onTap,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius: BorderRadius.circular(999),
              ),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(price,
                      style: AppTextStyles.bodyStrong(color: Colors.white)
                          .copyWith(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceSkeleton extends StatelessWidget {
  const _PerformanceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 236,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(height: 12, width: 90),
              SizedBox(height: 10),
              SkeletonBox(height: 28, width: 130),
              SizedBox(height: 18),
              Expanded(child: SkeletonBox(height: double.infinity)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(child: SkeletonBox(height: 104, radius: AppRadius.md)),
            SizedBox(width: 14),
            Expanded(child: SkeletonBox(height: 104, radius: AppRadius.md)),
          ],
        ),
      ],
    );
  }
}
