import 'package:flutter/material.dart';

import '../models/property.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/pill_button.dart';
import '../widgets/property_image.dart';
import 'share_sheet.dart';

/// Screen 19 — side-by-side comparison, reached from the Fair Price sheet.
///
/// ## Where the green ticks come from
///
/// The Figma marks the better value in each row with a green tick. That's a
/// derived judgement, not data, so it lives in [_Row.winner] and is computed
/// once per row by [_rows] — never hardcoded per column. "Better" is not always
/// "bigger": rent and price-per-sqft are better when lower, area and rating
/// when higher, and some rows (furnishing) have no natural winner and get no
/// tick at all. Keeping that in one place is what stops the two columns from
/// disagreeing when real data arrives.
///
/// The right-hand column is a [ComparableListing], not a full [Property] — that's all
/// the comparables endpoint returns. Fields the comparable doesn't carry
/// (verified, rating, furnishing, parking) render as a dash rather than being
/// invented, and [_Row.winner] skips any row where either side is unknown.
class CompareScreen extends StatelessWidget {
  final Property property;
  final ComparableListing other;

  const CompareScreen({
    super.key,
    required this.property,
    required this.other,
  });

  @override
  Widget build(BuildContext context) {
    final rows = _rows(property, other);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              onBack: () => Navigator.of(context).maybePop(),
              onShare: () => ShareSheet.show(context, property),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  _ColumnHeads(property: property, other: other),
                  const SizedBox(height: 8),
                  for (final row in rows) _RowView(row: row),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenPadding),
                    child: Row(
                      children: [
                        const SizedBox(width: _labelWidth),
                        Expanded(
                          child: PrimaryButton(
                            label: 'Enquire',
                            onTap: () {},
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GhostButton(
                            label: 'Enquire',
                            onTap: () {},
                          ),
                        ),
                      ],
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

  static const double _labelWidth = 96;

  /// Builds every comparison row and decides which side wins each one.
  static List<_Row> _rows(Property p, ComparableListing c) {
    final rentLabel = p.period == null ? 'Price' : 'Rent / ${p.period!.label}';
    final cPerSqft = c.sqft == 0 ? 0 : (c.price / c.sqft).round();

    return [
      _Row(
        label: rentLabel,
        left: '${p.currency} ${p.priceFormatted}',
        right: '${c.currency} ${formatThousands(c.price)}',
        // Cheaper wins.
        winner: _lower(p.price, c.price),
      ),
      _Row(
        label: 'Per sqft',
        left: '${p.pricePerSqft}',
        right: cPerSqft == 0 ? null : '$cPerSqft',
        winner: cPerSqft == 0 ? null : _lower(p.pricePerSqft, cPerSqft),
      ),
      _Row(
        label: 'BUA',
        left: '${formatThousands(p.sqft)} sqft',
        right: c.sqft == 0 ? null : '${formatThousands(c.sqft)} sqft',
        // More space wins.
        winner: c.sqft == 0 ? null : _higher(p.sqft, c.sqft),
      ),
      _Row(
        label: 'Fair price',
        left: p.fairPrice.verdictLabel,
        // The comparables endpoint doesn't return a verdict per comparable.
        right: null,
        leftChip: _chipFor(p.fairPrice.verdict),
        winner: null,
      ),
      _Row(
        label: 'Beds',
        left: '${p.beds}',
        right: c.beds == 0 ? null : '${c.beds}',
        winner: c.beds == 0 ? null : _higher(p.beds, c.beds),
      ),
      _Row(
        label: 'Verified',
        left: p.verified ? 'Yes' : 'No',
        right: null,
        winner: p.verified ? _Side.left : null,
      ),
      _Row(
        label: 'Rating',
        left: p.rating == 0 ? null : '${p.rating}',
        right: null,
        leftSuffixStar: p.rating > 0,
        winner: null,
      ),
      _Row(
        label: 'Furnishing',
        left: p.furnishing ?? '—',
        right: null,
        // No natural better/worse — deliberately no tick.
        winner: null,
      ),
      _Row(
        label: 'Availability',
        left: 'Listed now',
        right: c.recency.isEmpty ? null : _capitalise(c.recency),
        winner: null,
      ),
    ];
  }

  static _Side? _lower(int a, int b) =>
      a == b ? null : (a < b ? _Side.left : _Side.right);

  static _Side? _higher(int a, int b) =>
      a == b ? null : (a > b ? _Side.left : _Side.right);

  static ({Color bg, Color fg})? _chipFor(PriceVerdict v) => switch (v) {
        PriceVerdict.low => (bg: const Color(0xFFE7F4EC), fg: AppColors.success),
        PriceVerdict.fair =>
          (bg: const Color(0xFFE7F4EC), fg: AppColors.success),
        PriceVerdict.high =>
          (bg: AppColors.accentTint, fg: AppColors.warning),
      };

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

enum _Side { left, right }

class _Row {
  final String label;
  final String? left;
  final String? right;
  final _Side? winner;
  final ({Color bg, Color fg})? leftChip;
  final bool leftSuffixStar;

  const _Row({
    required this.label,
    required this.left,
    required this.right,
    required this.winner,
    this.leftChip,
    this.leftSuffixStar = false,
  });
}

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onShare;

  const _Header({required this.onBack, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.arrow_back_rounded,
                  color: AppColors.ink, size: 24),
            ),
          ),
          Expanded(
            child: Text(
              'Compare',
              textAlign: TextAlign.center,
              style: AppTextStyles.h1().copyWith(fontSize: 22),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onShare,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.ios_share_rounded,
                  color: AppColors.ink, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnHeads extends StatelessWidget {
  final Property property;
  final ComparableListing other;

  const _ColumnHeads({required this.property, required this.other});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: CompareScreen._labelWidth),
          Expanded(
            child: _Head(
              seed: property.gradientSeed,
              url: property.photos.isEmpty ? null : property.photos.first,
              title: property.title,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Head(
              seed: other.gradientSeed,
              url: other.photoUrl,
              title: other.label,
            ),
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  final int seed;
  final String? url;
  final String title;

  const _Head({required this.seed, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1.05,
          child: PropertyImage(
            seed: seed,
            url: url,
            decodeWidth: MediaQuery.sizeOf(context).width / 2,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyStrong().copyWith(fontSize: 16),
        ),
      ],
    );
  }
}

class _RowView extends StatelessWidget {
  final _Row row;
  const _RowView({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding, vertical: 15),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: CompareScreen._labelWidth,
            child: Text(row.label, style: AppTextStyles.caption()),
          ),
          Expanded(
            child: _Cell(
              value: row.left,
              won: row.winner == _Side.left,
              chip: row.leftChip,
              star: row.leftSuffixStar,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Cell(
              value: row.right,
              won: row.winner == _Side.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String? value;
  final bool won;
  final ({Color bg, Color fg})? chip;
  final bool star;

  const _Cell({
    required this.value,
    required this.won,
    this.chip,
    this.star = false,
  });

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return Text('—', style: AppTextStyles.body(color: AppColors.inkMuted));
    }

    if (chip != null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: chip!.bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            value!,
            style: AppTextStyles.micro(color: chip!.fg)
                .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    final color = won ? AppColors.success : AppColors.ink;

    return Row(
      children: [
        Flexible(
          child: Text(
            value!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: won
                ? AppTextStyles.bodyStrong(color: color)
                : AppTextStyles.body(color: color),
          ),
        ),
        if (star) ...[
          const SizedBox(width: 3),
          Icon(Icons.star_rounded, size: 15, color: color),
        ],
        if (won) ...[
          const SizedBox(width: 5),
          const Icon(Icons.check_rounded, size: 16, color: AppColors.success),
        ],
      ],
    );
  }
}
