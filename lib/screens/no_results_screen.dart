import 'package:flutter/material.dart';

import '../models/search_query.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/pill_button.dart';

/// Screen 17, as an embeddable view rather than a route.
///
/// The results screen shows this inline when the query genuinely returns
/// nothing, so it's reachable by actually over-filtering instead of by a debug
/// "preview empty state" link.
///
/// The relax suggestions are derived from the live query. When the backend
/// starts returning facet counts, swap [_suggestionsFor] for the real ones —
/// the layout doesn't change.
class NoResultsView extends StatelessWidget {
  final SearchQuery query;
  final VoidCallback onEditFilters;
  final VoidCallback onSaveSearch;

  const NoResultsView({
    super.key,
    required this.query,
    required this.onEditFilters,
    required this.onSaveSearch,
  });

  List<String> _suggestionsFor(SearchQuery q) {
    final out = <String>[];
    if (q.priceMax != null) {
      out.add('Raise your budget above '
          'AED ${formatThousandsCompact(q.priceMax!)}');
    }
    if (q.amenities.isNotEmpty) {
      out.add('Drop the ${q.amenities.first} requirement');
    }
    if (q.beds != null && q.beds! > 1) {
      out.add('Include ${q.beds! - 1}-bed homes');
    }
    if (q.verifiedOnly) out.add('Include listings pending verification');
    if (q.community != null) out.add('Search nearby communities too');
    if (out.isEmpty) out.add('Try a wider area or a different property type');
    return out.take(3).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestionsFor(query);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding, 32, AppSpacing.screenPadding, 24),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.search_off_rounded,
                color: AppColors.accent, size: 36),
          ),
          const SizedBox(height: 22),
          Text('No homes match — yet',
              style: AppTextStyles.h1(), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'Nothing fits all your filters'
            '${query.community != null ? " in ${query.community}" : ""} right '
            'now. Try relaxing one of these:',
            style: AppTextStyles.body(color: AppColors.inkMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          for (final suggestion in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(suggestion, style: AppTextStyles.bodyStrong()),
              ),
            ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Save search & alert me',
            leadingIcon: Icons.notifications_none_rounded,
            onTap: onSaveSearch,
          ),
          const SizedBox(height: 12),
          GhostButton(label: 'Edit filters', onTap: onEditFilters),
        ],
      ),
    );
  }
}

String formatThousandsCompact(int value) {
  if (value >= 1000000) {
    final m = value / 1000000;
    return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
  }
  if (value >= 1000) return '${(value / 1000).round()}k';
  return '$value';
}
