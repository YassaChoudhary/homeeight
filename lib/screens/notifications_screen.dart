import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'settings_screen.dart';

/// Screen F09 — "Notifications".
///
/// Two groups with different meanings: **channels** are how we reach you,
/// **topics** are what we reach you about. Turning off every channel doesn't
/// clear the topics, because the topics are still what you'd want if you turned
/// a channel back on.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SettingsHeader(title: 'Notifications'),
            Expanded(
              child: AppStateBuilder(
                builder: (context, state) => ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding, 4, AppSpacing.screenPadding, 28),
                  children: [
                    const _GroupLabel('CHANNELS'),
                    const SizedBox(height: 10),
                    SettingsCard(
                      rows: [
                        SettingsRow(
                          icon: Icons.notifications_none_rounded,
                          label: 'Push',
                          toggleValue: state.pushEnabled,
                          onToggle: state.setPushEnabled,
                        ),
                        SettingsRow(
                          icon: Icons.mail_outline_rounded,
                          label: 'Email',
                          toggleValue: state.emailEnabled,
                          onToggle: state.setEmailEnabled,
                        ),
                        SettingsRow(
                          icon: Icons.smartphone_rounded,
                          label: 'SMS',
                          toggleValue: state.smsEnabled,
                          onToggle: state.setSmsEnabled,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const _GroupLabel('WHAT YOU GET'),
                    const SizedBox(height: 10),
                    SettingsCard(
                      rows: [
                        SettingsRow(
                          label: 'New matches',
                          subtitle: 'Saved searches get new listings',
                          toggleValue: state.notifTopic('matches'),
                          onToggle: (v) => state.setNotifTopic('matches', v),
                        ),
                        SettingsRow(
                          label: 'Price drops',
                          subtitle: 'On saved homes',
                          toggleValue: state.notifTopic('price_drops'),
                          onToggle: (v) =>
                              state.setNotifTopic('price_drops', v),
                        ),
                        SettingsRow(
                          label: 'Messages',
                          subtitle: 'Chats and viewing confirmations',
                          toggleValue: state.notifTopic('messages'),
                          onToggle: (v) => state.setNotifTopic('messages', v),
                        ),
                        SettingsRow(
                          label: 'Offers & tips',
                          subtitle: 'Promotions and market reports',
                          toggleValue: state.notifTopic('offers'),
                          onToggle: (v) => state.setNotifTopic('offers', v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _QuietHoursNote(
                      onTap: () => ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Quiet hours is work in progress — coming soon.'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppColors.navDark,
                          ),
                        ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.micro(color: AppColors.inkMuted)
          .copyWith(fontSize: 12.5, letterSpacing: 0.7),
    );
  }
}

class _QuietHoursNote extends StatelessWidget {
  final VoidCallback onTap;
  const _QuietHoursNote({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.notifications_paused_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: AppTextStyles.body(color: AppColors.primaryDark)
                      .copyWith(fontSize: 14, height: 1.45),
                  children: [
                    TextSpan(
                      text: 'Quiet hours 10 PM – 8 AM',
                      style: AppTextStyles.bodyStrong(
                              color: AppColors.primaryDark)
                          .copyWith(fontSize: 14),
                    ),
                    const TextSpan(
                        text: ' — pushes are held overnight. Tap to change.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
