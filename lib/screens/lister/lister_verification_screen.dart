import 'package:flutter/material.dart';

import '../../core/async_value.dart';
import '../../data/listing_repository.dart';
import '../../models/lister_profile.dart';
import '../../models/uploaded_doc.dart';
import '../../state/app_scope.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/media_picker.dart';
import '../../widgets/pill_button.dart';
import 'verification_submitted_screen.dart';

/// Prototype 63 / 64 / 65 — the verification form for the chosen type.
///
/// * Individual: Legal Name · Government Issued ID card (front, back)
/// * Agent:      Associated Company · RERA / licence number · Trade licence
/// * Company:    Company name · RERA / licence number · Trade licence
///
/// Files go to the PRIVATE Storage bucket (only this account and the Home8
/// team can open them). Submitting creates a pending request; you approve it
/// in Supabase with `review_verification`.
class ListerVerificationScreen extends StatefulWidget {
  final ListerType type;

  /// Runs after a successful submit (this screen is closed first).
  final VoidCallback? onDone;

  const ListerVerificationScreen({super.key, required this.type, this.onDone});

  @override
  State<ListerVerificationScreen> createState() =>
      _ListerVerificationScreenState();
}

enum _Slot { idFront, idBack, tradeLicence }

class _ListerVerificationScreenState extends State<ListerVerificationScreen> {
  late final TextEditingController _name;
  late final TextEditingController _organisation;
  late final TextEditingController _licence;

  UploadedDoc? _idFront;
  UploadedDoc? _idBack;
  UploadedDoc? _tradeLicence;
  _Slot? _uploading;
  bool _submitting = false;

  bool get _individual => widget.type == ListerType.individual;

  @override
  void initState() {
    super.initState();
    final user = AppScope.authOf(context).user;
    final previous = user?.listerProfile;
    final sameType = previous?.type == widget.type;
    _name = TextEditingController(
      text: sameType && (previous?.legalName.isNotEmpty ?? false)
          ? previous!.legalName
          : (user?.name ?? ''),
    );
    _organisation = TextEditingController(
        text: sameType ? (previous?.organisation ?? '') : '');
    _licence = TextEditingController(
        text: sameType ? (previous?.licenceNumber ?? '') : '');
  }

  @override
  void dispose() {
    _name.dispose();
    _organisation.dispose();
    _licence.dispose();
    super.dispose();
  }

  bool get _canSubmit => _individual
      ? _name.text.trim().isNotEmpty && _idFront != null && _idBack != null
      : _organisation.text.trim().isNotEmpty &&
          _licence.text.trim().isNotEmpty &&
          _tradeLicence != null;

  void _tell(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navDark,
      ));
  }

  Future<void> _upload(_Slot slot) async {
    if (_uploading != null) return;
    final file = slot == _Slot.tradeLicence
        ? await MediaPicker.document(context)
        : await MediaPicker.photo(context, preferFront: false);
    if (file == null || !mounted) return;
    setState(() => _uploading = slot);
    try {
      final stored = await AppScope.repositoryOf(context).uploadListingFile(
        kind: ListingFileKind.privateDoc,
        bytes: file.bytes,
        fileName: switch (slot) {
          _Slot.idFront => 'Front of card${_ext(file.name)}',
          _Slot.idBack => 'Back of card${_ext(file.name)}',
          _Slot.tradeLicence => file.name,
        },
        contentType: file.mimeType,
      );
      if (!mounted) return;
      setState(() {
        switch (slot) {
          case _Slot.idFront:
            _idFront = stored;
          case _Slot.idBack:
            _idBack = stored;
          case _Slot.tradeLicence:
            _tradeLicence = stored;
        }
      });
    } catch (e) {
      if (mounted) {
        _tell(e is RepositoryException ? e.message : "Couldn't upload. Try again.");
      }
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '.jpg' : name.substring(dot).toLowerCase();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() => _submitting = true);

    final auth = AppScope.authOf(context);
    final repo = AppScope.repositoryOf(context);
    final profile = ListerProfile(
      type: widget.type,
      legalName: _individual ? _name.text.trim() : '',
      organisation: _individual ? '' : _organisation.text.trim(),
      licenceNumber: _individual ? '' : _licence.text.trim(),
      idFront: _individual ? _idFront : null,
      idBack: _individual ? _idBack : null,
      tradeLicence: _individual ? null : _tradeLicence,
      status: VerificationStatus.pending,
    );

    try {
      final saved = await repo.submitVerification(profile);
      if (!mounted) return;
      if (_individual && _name.text.trim().isNotEmpty) {
        auth.updateProfile(name: _name.text.trim());
      }
      auth.setListerProfile(saved);
      // "Verification submitted for review" → Go to my dashboard.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerificationSubmittedScreen(profile: saved),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _tell(e is RepositoryException
          ? e.message
          : "We couldn't send your documents. Check your connection and try again.");
    }
  }

  Widget _fileSlot(_Slot slot, UploadedDoc? doc, String emptyLabel) {
    if (_uploading == slot) {
      return const _UploadingRow();
    }
    if (doc == null) {
      return DashedAddTile(
        label: emptyLabel,
        icon: Icons.upload_file_rounded,
        height: 78,
        onTap: () => _upload(slot),
      );
    }
    return UploadedRow(
      fileName: doc.name,
      statusLine: doc.statusLine,
      icon: Icons.task_outlined,
      actionLabel: 'Replace',
      onAction: () => _upload(slot),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;

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
                  Text(type.verifyTitle,
                      style: AppTextStyles.display().copyWith(fontSize: 28)),
                  const SizedBox(height: 8),
                  Text(
                    type.verifySubtitle,
                    style: AppTextStyles.body(color: AppColors.inkMuted)
                        .copyWith(fontSize: 15.5, height: 23 / 15.5),
                  ),
                  const SizedBox(height: 26),
                  if (_individual) ...[
                    const FieldLabel('Legal Name'),
                    const SizedBox(height: 10),
                    AppTextField(
                      controller: _name,
                      hint: 'Name exactly as on your ID',
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 22),
                    const FieldLabel('Government Issued ID card'),
                    const SizedBox(height: 10),
                    _fileSlot(_Slot.idFront, _idFront, 'Upload front of card'),
                    const SizedBox(height: 14),
                    _fileSlot(_Slot.idBack, _idBack, 'Upload back of card'),
                  ] else ...[
                    FieldLabel(type.organisationLabel),
                    const SizedBox(height: 10),
                    AppTextField(
                      controller: _organisation,
                      hint: type == ListerType.company
                          ? 'Registered company name'
                          : 'Company you work with',
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 22),
                    const FieldLabel('RERA / licence number'),
                    const SizedBox(height: 10),
                    AppTextField(
                      controller: _licence,
                      hint: 'e.g. 44921',
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 22),
                    const FieldLabel('Trade licence'),
                    const SizedBox(height: 10),
                    _fileSlot(_Slot.tradeLicence, _tradeLicence,
                        'Upload trade licence (PDF or photo)'),
                  ],
                  const SizedBox(height: 26),
                  const InfoNote(
                    tone: NoteTone.warning,
                    icon: Icons.schedule_rounded,
                    message: 'Review takes up to 1 business day. You can '
                        'browse and save while pending, but listings stay in '
                        'draft until approved.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding, 4, AppSpacing.screenPadding, 12),
              child: PrimaryButton(
                label: 'Submit for verification',
                loading: _submitting,
                onTap: _canSubmit && _uploading == null ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadingRow extends StatelessWidget {
  const _UploadingRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(width: 14),
          Text('Uploading…', style: AppTextStyles.bodyStrong()),
        ],
      ),
    );
  }
}
