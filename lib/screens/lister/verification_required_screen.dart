import 'package:flutter/material.dart';

import '../../models/lister_profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/pill_button.dart';
import 'lister_verification_screen.dart';

/// Prototype 62 — "Verification Required".
///
/// Only verified individuals, agents and real estate companies can publish.
/// Shown when someone taps + without a verified account, and during
/// onboarding when they choose "List a property". The chosen type opens the
/// matching form (prototype 63 / 64 / 65).
class VerificationRequiredScreen extends StatefulWidget {
  /// Runs after the form is submitted (both screens are closed first).
  final VoidCallback? onDone;

  /// Type to pre-select (e.g. what they chose last time).
  final ListerType? initialType;

  /// Shown when the last request was rejected.
  final String rejectionNote;

  const VerificationRequiredScreen({
    super.key,
    this.onDone,
    this.initialType,
    this.rejectionNote = '',
  });

  @override
  State<VerificationRequiredScreen> createState() =>
      _VerificationRequiredScreenState();
}

class _VerificationRequiredScreenState
    extends State<VerificationRequiredScreen> {
  late ListerType _type = widget.initialType ?? ListerType.individual;

  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListerVerificationScreen(
          type: _type,
          // The form pops itself, then this closes too and hands over.
          onDone: _finish,
        ),
      ),
    );
  }

  void _finish() {
    Navigator.of(context).pop();
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Icon(Icons.arrow_back_rounded,
                      color: AppColors.ink, size: 24),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding, 18, AppSpacing.screenPadding, 20),
                children: [
                  Text('Verification Required',
                      style: AppTextStyles.display().copyWith(fontSize: 28)),
                  const SizedBox(height: 10),
                  Text(
                    'To continue adding the property please verify yourself',
                    style: AppTextStyles.body(color: AppColors.inkMuted)
                        .copyWith(fontSize: 15.5, height: 22 / 15.5),
                  ),
                  if (widget.rejectionNote.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    InfoNote(
                      tone: NoteTone.warning,
                      icon: Icons.error_outline_rounded,
                      message: 'Your last request wasn\'t approved: '
                          '${widget.rejectionNote}. Please submit again.',
                    ),
                  ],
                  const SizedBox(height: 22),
                  for (final type in ListerType.values) ...[
                    _TypeCard(
                      type: type,
                      selected: _type == type,
                      onTap: () => setState(() => _type = type),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding, 4, AppSpacing.screenPadding, 12),
              child: PrimaryButton(label: 'Continue', onTap: _continue),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final ListerType type;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  Color get _iconBg => switch (type) {
        ListerType.individual => AppColors.primaryTint,
        ListerType.agent => const Color(0xFFFCEBD2),
        ListerType.company => const Color(0xFFFBDADA),
      };

  Color get _iconTint => switch (type) {
        ListerType.individual => AppColors.primary,
        ListerType.agent => AppColors.amber,
        ListerType.company => AppColors.danger,
      };

  IconData get _icon => switch (type) {
        ListerType.individual => Icons.person_outline_rounded,
        ListerType.agent => Icons.work_outline_rounded,
        ListerType.company => Icons.work_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg + 4),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.line,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: _iconBg,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(_icon, color: _iconTint, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.label,
                      style: AppTextStyles.h2().copyWith(fontSize: 18)),
                  const SizedBox(height: 3),
                  Text(type.blurb,
                      style: AppTextStyles.body(color: AppColors.inkMuted)
                          .copyWith(fontSize: 14.5, height: 20 / 14.5)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.line,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 18)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
