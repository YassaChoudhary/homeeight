import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'settings_screen.dart';

// ---------------------------------------------------------------------------
// F07 — Help & support
// ---------------------------------------------------------------------------

/// Screen F07.
///
/// The article counts and the popular list are static copy: there is no help
/// CMS, and inventing a `HelpRepository` for text that will come from a content
/// system later would be architecture for its own sake. The search field is
/// present but disabled-by-behaviour for the same reason — it says so when
/// tapped rather than pretending to search nothing.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const List<(IconData, Color, Color, String, String)> _categories = [
    (Icons.home_outlined, AppColors.primary, AppColors.primaryTint,
        'Renting & buying', '12 articles'),
    (Icons.add_rounded, AppColors.amber, Color(0xFFFCF0DC), 'Posting listings',
        '9 articles'),
    (Icons.verified_user_outlined, AppColors.success, Color(0xFFE7F4EC),
        'Verification & safety', '7 articles'),
    (Icons.credit_card_outlined, AppColors.inkMuted, Color(0xFFEFF2F3),
        'Payments & billing', '6 articles'),
  ];

  static const List<String> _popular = [
    'How does the fair-price band work?',
    'Why is my listing pending review?',
    'How do I avoid rental scams?',
  ];

  void _notYet(BuildContext context, String what) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SettingsHeader(title: 'Help & support'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding, 4, AppSpacing.screenPadding, 20),
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _notYet(context, 'Help search'),
                    child: Container(
                      height: 62,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded,
                              color: AppColors.inkMuted, size: 21),
                          const SizedBox(width: 12),
                          Text('Search help articles',
                              style: AppTextStyles.body(
                                      color: AppColors.inkMuted)
                                  .copyWith(fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.12,
                    children: [
                      for (final (icon, tint, bg, title, count) in _categories)
                        _CategoryCard(
                          icon: icon,
                          iconTint: tint,
                          iconBg: bg,
                          title: title,
                          count: count,
                          onTap: () => _notYet(context, title),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'POPULAR',
                    style: AppTextStyles.micro(color: AppColors.inkMuted)
                        .copyWith(fontSize: 12.5, letterSpacing: 0.7),
                  ),
                  const SizedBox(height: 6),
                  for (final q in _popular)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _notYet(context, 'Help articles'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE3E9E9)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(q,
                                  style: AppTextStyles.body()
                                      .copyWith(fontSize: 16)),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: AppColors.inkMuted, size: 22),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding, 8, AppSpacing.screenPadding, 10),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _notYet(context, 'Support chat'),
                child: Container(
                  height: 62,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.navDark,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      Text('Chat with support',
                          style: AppTextStyles.bodyStrong(color: Colors.white)
                              .copyWith(fontSize: 17)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final Color iconTint;
  final Color iconBg;
  final String title;
  final String count;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.icon,
    required this.iconTint,
    required this.iconBg,
    required this.title,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: iconTint, size: 24),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyStrong().copyWith(fontSize: 15.5),
            ),
            const SizedBox(height: 4),
            Text(count, style: AppTextStyles.caption()),
          ],
        ),
      ),
    );
  }
}
