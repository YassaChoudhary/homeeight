import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Round avatar with an optional green "online" dot — inbox rows, chat
/// header and agent profile.
class ChatAvatar extends StatelessWidget {
  final String? url;
  final String initials;
  final double size;
  final bool online;

  /// Ring colour behind the online dot (matches what it sits on).
  final Color dotBorder;

  const ChatAvatar({
    super.key,
    required this.url,
    required this.initials,
    this.size = 54,
    this.online = false,
    this.dotBorder = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: AppColors.primaryTint,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTextStyles.bodyStrong(color: AppColors.primaryDark)
            .copyWith(fontSize: size * 0.34),
      ),
    );
    final dot = size * 0.27;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: SizedBox(
              width: size,
              height: size,
              child: url == null || url!.isEmpty
                  ? fallback
                  : Image.network(
                      url!,
                      fit: BoxFit.cover,
                      cacheWidth: (size * 3).round(),
                      errorBuilder: (_, _, _) => fallback,
                    ),
            ),
          ),
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: dotBorder, width: size * 0.045),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Soft shadow used by the white cards on the chat and profile screens.
const List<BoxShadow> softCardShadow = [
  BoxShadow(
    color: Color(0x0F1B2336),
    blurRadius: 24,
    offset: Offset(0, 8),
  ),
];

/// The teal glow under primary pill buttons and outgoing bubbles.
List<BoxShadow> tealGlow([double strength = 1]) => [
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.32 * strength),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ];

/// Shown wherever a call button lives — calls aren't built yet.
void showCallsComingSoon(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.call_outlined,
                  color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 18),
            Text('Calls are coming soon',
                textAlign: TextAlign.center,
                style: AppTextStyles.h2().copyWith(fontSize: 20)),
            const SizedBox(height: 8),
            Text(
              "In-app voice calls are on the way. For now, keep chatting "
              'here — or use Call / WhatsApp on the listing.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: AppColors.inkMuted)
                  .copyWith(fontSize: 14.5, height: 21 / 14.5),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: tealGlow(0.7),
                ),
                child: Text('Got it',
                    style: AppTextStyles.bodyStrong(color: Colors.white)
                        .copyWith(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
