import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/property.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/pill_button.dart';
import '../widgets/property_image.dart';

/// Screen 17 — "Share this home".
///
/// Opened from the share button on the property detail gallery and from the
/// Gallery screen's own share button.
///
/// **On the share targets:** tapping WhatsApp / Message / Email should hand off
/// to the OS share sheet, which needs a plugin (`share_plus`, or
/// `url_launcher` for the per-channel deep links). No dependencies were added
/// here, so each target currently copies the link and confirms with a snackbar,
/// and [_ShareTarget.onTap] is the single place to swap in the real intent.
/// The share URL itself comes from [shareUrl] rather than being built inline,
/// so it can move to a backend-provided canonical link without touching layout.
class ShareSheet extends StatelessWidget {
  final Property property;

  const ShareSheet({super.key, required this.property});

  /// Deep link for the listing. Matches the shareable-URL shape the blueprint
  /// asks for; becomes a real link once `go_router` and the web host exist.
  String get shareUrl {
    final slug = property.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final permit = property.permitNo;
    return 'home8.app/l/$slug${permit == null ? '' : '-$permit'}';
  }

  static Future<void> show(BuildContext context, Property property) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => ShareSheet(property: property),
    );
  }

  Future<void> _copy(BuildContext context, {String? confirmation}) async {
    await Clipboard.setData(ClipboardData(text: 'https://$shareUrl'));
    if (!context.mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(confirmation ?? 'Link copied'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navDark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = property;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg + 8),
          topRight: Radius.circular(AppRadius.lg + 8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: SheetDragHandle()),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text('Share this home',
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
              const SizedBox(height: 18),
              _ListingPreview(property: p),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _ShareTarget(
                      label: 'WhatsApp',
                      icon: Icons.chat_rounded,
                      bg: const Color(0xFF25D366),
                      glow: true,
                      onTap: () =>
                          _copy(context, confirmation: 'Link copied for WhatsApp'),
                    ),
                  ),
                  Expanded(
                    child: _ShareTarget(
                      label: 'Message',
                      icon: Icons.sms_rounded,
                      bg: AppColors.primary,
                      glow: true,
                      onTap: () =>
                          _copy(context, confirmation: 'Link copied for Messages'),
                    ),
                  ),
                  Expanded(
                    child: _ShareTarget(
                      label: 'Email',
                      icon: Icons.mail_outline_rounded,
                      bg: AppColors.navDark,
                      onTap: () =>
                          _copy(context, confirmation: 'Link copied for email'),
                    ),
                  ),
                  Expanded(
                    child: _ShareTarget(
                      label: 'More',
                      icon: Icons.more_horiz_rounded,
                      bg: const Color(0xFFEFF2F3),
                      fg: AppColors.ink,
                      onTap: () => _copy(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _LinkRow(url: shareUrl, onCopy: () => _copy(context)),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListingPreview extends StatelessWidget {
  final Property property;
  const _ListingPreview({required this.property});

  @override
  Widget build(BuildContext context) {
    final p = property;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F7),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            height: 62,
            child: PropertyImage(
              seed: p.gradientSeed,
              url: p.photos.isEmpty ? null : p.photos.first,
              decodeWidth: 62,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyStrong().copyWith(fontSize: 16),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    '${p.currency} ${p.priceFormatted}'
                        '${p.period == null ? '' : ' / ${p.period!.label}'}',
                    '${p.beds} Bed',
                    '${formatThousands(p.sqft)} sqft',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareTarget extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final bool glow;
  final VoidCallback onTap;

  const _ShareTarget({
    required this.label,
    required this.icon,
    required this.bg,
    required this.onTap,
    this.fg = Colors.white,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: glow
                  ? [
                      BoxShadow(
                        color: bg.withValues(alpha: 0.38),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon, color: fg, size: 26),
          ),
          const SizedBox(height: 9),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption(color: AppColors.ink)
                .copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final String url;
  final VoidCallback onCopy;

  const _LinkRow({required this.url, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 6),
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 20, color: AppColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(color: AppColors.inkMuted),
            ),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: onCopy,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('Copy',
                  style: AppTextStyles.bodyStrong(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
