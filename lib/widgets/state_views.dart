import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'listing_card.dart';
import 'pill_button.dart';

/// Shimmer-free skeleton block. A plain animated opacity costs far less than a
/// gradient sweep and reads the same at these sizes.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 0.85).animate(_controller),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.line.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// Placeholder shaped like a [DealCard], used while the carousel loads.
class DealCardSkeleton extends StatelessWidget {
  final double width;
  const DealCardSkeleton({super.key, this.width = DealCard.defaultWidth});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: DealCard.height,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: DealCard.imageHeight, radius: 0),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 14, width: 150),
                  SizedBox(height: 10),
                  SkeletonBox(height: 12, width: 190),
                  SizedBox(height: 10),
                  SkeletonBox(height: 14, width: 120),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder shaped like a [ResultListingCard].
class ResultCardSkeleton extends StatelessWidget {
  const ResultCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: ResultListingCard.imageHeight, radius: 0),
          Padding(
            padding: EdgeInsets.all(AppSpacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 16, width: 200),
                SizedBox(height: 12),
                SkeletonBox(height: 12, width: 240),
                SizedBox(height: 12),
                SkeletonBox(height: 16, width: 160),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Friendly failure with a retry. Every async surface renders this on error, so
/// a flaky backend never produces a blank screen.
class ErrorStateView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  const ErrorStateView({
    super.key,
    this.message = "We couldn't load this right now.",
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.s4, vertical: compact ? 20 : 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 56 : 76,
            height: compact ? 56 : 76,
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(compact ? 18 : 24),
            ),
            child: Icon(Icons.cloud_off_rounded,
                color: AppColors.accent, size: compact ? 24 : 32),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.body(color: AppColors.inkMuted),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            GhostButton(
              label: 'Try again',
              leadingIcon: Icons.refresh_rounded,
              expand: false,
              onTap: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// Generic empty state for lists that aren't the dedicated "No homes match"
/// screen (saved, chats, notifications).
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyStateView({
    super.key,
    this.icon = Icons.inbox_rounded,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s6, vertical: AppSpacing.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: AppColors.accent, size: 32),
          ),
          const SizedBox(height: 18),
          Text(title, style: AppTextStyles.h2(), textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: AppColors.inkMuted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}
