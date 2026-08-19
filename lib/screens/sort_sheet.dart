import 'package:flutter/material.dart';

import '../models/search_query.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/pill_button.dart';

/// Screen 16. Returns the chosen [SortOption] through `Navigator.pop` rather
/// than mutating anything, so the caller owns the query.
class SortSheet extends StatefulWidget {
  final SortOption selected;
  const SortSheet({super.key, this.selected = SortOption.relevance});

  @override
  State<SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<SortSheet> {
  late SortOption _selected = widget.selected;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      child: Container(
        color: AppColors.surface,
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text('Sort by', style: AppTextStyles.h1()),
                  const SizedBox(height: 12),
                  for (var i = 0; i < SortOption.values.length; i++)
                    _SortRow(
                      option: SortOption.values[i],
                      selected: SortOption.values[i] == _selected,
                      isLast: i == SortOption.values.length - 1,
                      onTap: () =>
                          setState(() => _selected = SortOption.values[i]),
                    ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Apply',
                    onTap: () => Navigator.of(context).pop(_selected),
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

class _SortRow extends StatelessWidget {
  final SortOption option;
  final bool selected;
  final bool isLast;
  final VoidCallback onTap;

  const _SortRow({
    required this.option,
    required this.selected,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: isLast
            ? null
            : const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option.label,
                style:
                    selected ? AppTextStyles.bodyStrong() : AppTextStyles.body(),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.line,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
