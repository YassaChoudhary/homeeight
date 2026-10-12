import 'package:flutter/material.dart';

import '../../state/post_listing_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/media_picker.dart';
import '../../widgets/pill_button.dart';

/// Step 5 — "Verify your listing" (prototype screen 43).
///
/// * Title deed / Ejari — a PDF or photo, uploaded to a PRIVATE bucket.
/// * ID — photos of the front and back, private.
/// * Selfie — front camera, private. Unlocks after the ID, as designed.
/// * Permit number — shown on the listing ("Permit #…").
///
/// Only the owner (and you, in the Supabase dashboard) can open these files.
/// Required in the UAE; optional elsewhere but earns the Verified badge.
class StepPermit extends StatelessWidget {
  final PostListingController controller;

  const StepPermit({super.key, required this.controller});

  Future<void> _attachDeed(BuildContext context) async {
    final file = await MediaPicker.document(context);
    if (file == null) return;
    final ok = await controller.uploadDoc(DocSlot.titleDeed, file);
    if (!ok && context.mounted) _tell(context, controller.errorMessage);
  }

  /// Front, then back — two photos.
  Future<void> _scanId(BuildContext context) async {
    final draft = controller.draft;
    if (draft.idFront == null) {
      _tell(context, 'Photograph the FRONT of your ${draft.idDocumentName}.');
      final front = await MediaPicker.photo(context, preferFront: false);
      if (front == null || !context.mounted) return;
      final ok = await controller.uploadDoc(DocSlot.idFront, front);
      if (!context.mounted) return;
      if (!ok) {
        _tell(context, controller.errorMessage);
        return;
      }
    }
    if (controller.draft.idBack == null) {
      _tell(context, 'Now the BACK of your ${draft.idDocumentName}.');
      final back = await MediaPicker.photo(context, preferFront: false);
      if (back == null || !context.mounted) return;
      final ok = await controller.uploadDoc(DocSlot.idBack, back);
      if (!ok && context.mounted) _tell(context, controller.errorMessage);
    }
  }

  Future<void> _selfie(BuildContext context) async {
    if (!controller.draft.idScanned) return;
    final file =
        await MediaPicker.photo(context, preferFront: true, cameraOnly: true);
    if (file == null || !context.mounted) return;
    final ok = await controller.uploadDoc(DocSlot.selfie, file);
    if (!ok && context.mounted) _tell(context, controller.errorMessage);
  }

  static void _tell(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navDark,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final deed = draft.titleDeed;
    final deedBusy = controller.isUploading(DocSlot.titleDeed);
    final idBusy = controller.isUploading(DocSlot.idFront) ||
        controller.isUploading(DocSlot.idBack);
    final selfieBusy = controller.isUploading(DocSlot.selfie);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          draft.verificationRequired
              ? 'Required in the UAE market. Verified listings rank higher '
                  'and earn the badge.'
              : 'Optional in this market, but verified listings rank higher '
                  'and earn the badge.',
          style: AppTextStyles.body(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 20),
        _CheckRow(
          title: 'Title deed / Ejari',
          subtitle: deedBusy
              ? 'Uploading…'
              : deed == null
                  ? 'Tap to upload a PDF or photo'
                  : 'Uploaded · ${deed.name}',
          icon: deed == null
              ? Icons.description_outlined
              : Icons.task_outlined,
          state: deed != null ? _CheckState.done : _CheckState.pending,
          busy: deedBusy,
          actionLabel: 'Upload',
          // Tapping an uploaded deed replaces it.
          onTap: deedBusy ? null : () => _attachDeed(context),
        ),
        const SizedBox(height: 12),
        _CheckRow(
          title: draft.idDocumentName,
          subtitle: idBusy
              ? 'Uploading…'
              : draft.idScanned
                  ? 'Scanned · front & back'
                  : draft.idFront != null
                      ? 'Front done — tap to scan the back'
                      : 'Tap to scan front & back',
          icon: Icons.badge_outlined,
          state: draft.idScanned ? _CheckState.done : _CheckState.active,
          busy: idBusy,
          actionLabel: 'Scan',
          onTap: idBusy || draft.idScanned ? null : () => _scanId(context),
        ),
        const SizedBox(height: 12),
        _CheckRow(
          title: 'Selfie check',
          subtitle: selfieBusy
              ? 'Uploading…'
              : draft.selfieDone
                  ? 'Complete'
                  : draft.idScanned
                      ? 'Tap to take a quick selfie'
                      : 'Unlocks after ID scan',
          icon: Icons.smartphone_rounded,
          state: draft.selfieDone
              ? _CheckState.done
              : draft.idScanned
                  ? _CheckState.active
                  : _CheckState.locked,
          busy: selfieBusy,
          actionLabel: 'Start',
          onTap: draft.idScanned && !draft.selfieDone && !selfieBusy
              ? () => _selfie(context)
              : null,
        ),
        const SizedBox(height: 20),
        _PermitNumberField(controller: controller),
        const SizedBox(height: 20),
        const _BenefitsPanel(),
      ],
    );
  }
}

/// Permit / advertising number — shown on the listing as "Permit #…".
class _PermitNumberField extends StatefulWidget {
  final PostListingController controller;
  const _PermitNumberField({required this.controller});

  @override
  State<_PermitNumberField> createState() => _PermitNumberFieldState();
}

class _PermitNumberFieldState extends State<_PermitNumberField> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.draft.permitNo);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final required = widget.controller.draft.verificationRequired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(required
            ? 'Permit number (Trakheesi / DLD)'
            : 'Permit number (optional)'),
        const SizedBox(height: 8),
        AppTextField(
          controller: _text,
          pill: true,
          icon: Icons.confirmation_number_outlined,
          hint: 'e.g. 7145-2201',
          textCapitalization: TextCapitalization.characters,
          onChanged: (t) =>
              widget.controller.edit((d) => d.copyWith(permitNo: t)),
        ),
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
  final bool busy;

  const _CheckRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.state,
    this.actionLabel,
    this.onTap,
    this.busy = false,
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: locked
              ? AppColors.surface.withValues(alpha: 0.6)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg + 4),
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
            if (busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
            else if (done)
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.navDark,
        borderRadius: BorderRadius.circular(AppRadius.lg + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined,
                  color: AppColors.primaryOnDark, size: 20),
              const SizedBox(width: 12),
              Text('What you get once verified',
                  style: AppTextStyles.bodyStrong(color: Colors.white)
                      .copyWith(fontSize: 16.5)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Verified badge on the card · higher search ranking · permit '
            'number shown on the listing · buyer trust score boost.',
            style: AppTextStyles.body(color: Colors.white70)
                .copyWith(fontSize: 14.5, height: 22 / 14.5),
          ),
        ],
      ),
    );
  }
}
