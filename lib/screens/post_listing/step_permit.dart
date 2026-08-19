import 'package:flutter/material.dart';

import '../../models/uploaded_doc.dart';
import '../../state/post_listing_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/pill_button.dart';

/// Screen 37 — "Verify your listing", the fields of step 4.
///
/// ## Three gates, in order
///
/// The document, then the ID, then the selfie. The selfie is deliberately
/// **locked until the ID scan is done** rather than merely disabled-looking: a
/// liveness check that can't be tied to a scanned document proves nothing, and
/// letting someone do them out of order means explaining a rejection later.
///
/// The lock is state on the draft (`idScanned`), not a local bool, so backing
/// out to Photos and returning doesn't silently unlock it.
class StepPermit extends StatelessWidget {
  final PostListingController controller;

  const StepPermit({super.key, required this.controller});

  /// Stands in for a file picker — see the note on `StepMedia`. Same one-line
  /// replacement when `file_picker` lands.
  void _attachDeed() {
    final reference = controller.draft.id ?? '71-4402';
    controller.edit(
      (d) => d.copyWith(
        titleDeed: UploadedDoc.simulated('deed-$reference.pdf', bytes: 940000),
      ),
    );
  }

  /// Stands in for the document-scanner SDK.
  void _scanId() => controller.edit((d) => d.copyWith(idScanned: true));

  void _selfie() {
    if (!controller.draft.idScanned) return;
    controller.edit((d) => d.copyWith(selfieDone: true));
  }

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final deed = draft.titleDeed;
    final uaeMarket = draft.countryCode == 'AE';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          uaeMarket
              ? 'Required in the UAE market. Verified listings rank higher '
                  'and earn the badge.'
              : 'Optional in this market, but verified listings rank higher '
                  'and earn the badge.',
          style: AppTextStyles.body(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 20),
        if (deed == null)
          _CheckRow(
            title: 'Title deed / Ejari',
            subtitle: 'Tap to upload a PDF or photo',
            icon: Icons.description_outlined,
            state: _CheckState.pending,
            actionLabel: 'Upload',
            onTap: _attachDeed,
          )
        else
          UploadedRow(
            fileName: 'Title deed / Ejari',
            statusLine: 'Uploaded · ${deed.name}',
            showTick: true,
          ),
        const SizedBox(height: 12),
        _CheckRow(
          title: 'Emirates ID',
          subtitle: draft.idScanned
              ? 'Scanned · front & back'
              : 'Tap to scan front & back',
          icon: Icons.badge_outlined,
          state: draft.idScanned ? _CheckState.done : _CheckState.active,
          actionLabel: draft.idScanned ? null : 'Scan',
          onTap: draft.idScanned ? null : _scanId,
        ),
        const SizedBox(height: 12),
        _CheckRow(
          title: 'Selfie check',
          subtitle: draft.selfieDone
              ? 'Complete'
              : draft.idScanned
                  ? 'Tap to take a quick selfie'
                  : 'Unlocks after ID scan',
          icon: Icons.face_retouching_natural_outlined,
          state: draft.selfieDone
              ? _CheckState.done
              : draft.idScanned
                  ? _CheckState.active
                  : _CheckState.locked,
          actionLabel: draft.idScanned && !draft.selfieDone ? 'Start' : null,
          onTap: draft.idScanned && !draft.selfieDone ? _selfie : null,
        ),
        const SizedBox(height: 20),
        const _BenefitsPanel(),
      ],
    );
  }
}

enum _CheckState { pending, active, done, locked }

/// One verification row. Four states, and the difference between them is
/// visible without reading the label — a locked row is grey with a padlock, an
/// active one has a teal border and a button.
class _CheckRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final _CheckState state;
  final String? actionLabel;
  final VoidCallback? onTap;

  const _CheckRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.state,
    this.actionLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final locked = state == _CheckState.locked;
    final done = state == _CheckState.done;
    final active = state == _CheckState.active;

    final iconBg = done
        ? const Color(0xFFE7F4EC)
        : locked
            ? const Color(0xFFEFF2F3)
            : AppColors.primaryTint;
    final iconFg = done
        ? AppColors.success
        : locked
            ? AppColors.inkMuted
            : AppColors.primary;

    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: locked
              ? AppColors.surface.withValues(alpha: 0.6)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.line,
            width: active ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 22, color: iconFg),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyStrong(
                      color: locked ? AppColors.inkMuted : AppColors.ink,
                    ).copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.caption(
                      color: done ? AppColors.success : AppColors.inkMuted,
                    ).copyWith(fontWeight: done ? FontWeight.w600 : FontWeight.w400),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (done)
              const Icon(Icons.check_rounded,
                  color: AppColors.success, size: 22)
            else if (locked)
              const Icon(Icons.lock_outline_rounded,
                  color: AppColors.inkMuted, size: 19)
            else if (actionLabel != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(actionLabel!,
                    style: AppTextStyles.bodyStrong(color: Colors.white)
                        .copyWith(fontSize: 14.5)),
              ),
          ],
        ),
      ),
    );
  }
}

/// The dark "What you get once verified" panel.
///
/// Kept as four separate lines rather than one paragraph because each is a
/// distinct promise, and a seller weighing up whether to hand over an ID scan
/// is reading for exactly that.
class _BenefitsPanel extends StatelessWidget {
  const _BenefitsPanel();

  static const List<String> _benefits = [
    'Verified badge on the card',
    'Higher search ranking',
    'Permit number shown on the listing',
    'Buyer trust score boost',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.navDark,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined,
                  color: AppColors.primaryOnDark, size: 19),
              const SizedBox(width: 10),
              Text('What you get once verified',
                  style: AppTextStyles.bodyStrong(color: Colors.white)
                      .copyWith(fontSize: 16.5)),
            ],
          ),
          const SizedBox(height: 14),
          for (final benefit in _benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(Icons.circle,
                        size: 5, color: AppColors.primaryOnDark),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      benefit,
                      style: AppTextStyles.body(color: Colors.white70)
                          .copyWith(fontSize: 14.5, height: 20 / 14.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
