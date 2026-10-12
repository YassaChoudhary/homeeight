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

/// Screen 29 — company / licence verification.
///
/// Only agents and companies land here; an individual selling their own home
/// verifies against the *property* at the permit step instead. See
/// `ListerType.needsAccountVerification`.
///
/// ## Pending is a real state
///
/// The amber note isn't decoration. A pending account can browse, save and
/// build listings, but those listings stay in draft until review passes — which
/// is enforced in `MyListingsScreen`, not just promised here. Saying so up
/// front is the difference between a wait and a bug report.
class VerifyCompanyScreen extends StatefulWidget {
  /// Same hold-the-intent contract as `CreateProfileScreen.onDone`.
  final VoidCallback? onDone;

  const VerifyCompanyScreen({super.key, this.onDone});

  @override
  State<VerifyCompanyScreen> createState() => _VerifyCompanyScreenState();
}

class _VerifyCompanyScreenState extends State<VerifyCompanyScreen> {
  late final TextEditingController _organisation;
  late final TextEditingController _licence;

  UploadedDoc? _tradeLicence;
  UploadedDoc? _brokerCard;
  bool _submitting = false;
  Object? _error;

  ListerType get _type =>
      AppScope.authOf(context).user?.listerType ?? ListerType.agent;

  @override
  void initState() {
    super.initState();
    final profile = AppScope.authOf(context).user?.listerProfile;
    _organisation = TextEditingController(text: profile?.organisation ?? '');
    _licence = TextEditingController(text: profile?.licenceNumber ?? '');
    _tradeLicence = profile?.tradeLicence;
    _brokerCard = profile?.brokerCard;
  }

  @override
  void dispose() {
    _organisation.dispose();
    _licence.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _organisation.text.trim().isNotEmpty &&
      _licence.text.trim().isNotEmpty &&
      _tradeLicence != null;

  /// Which document is uploading right now (null = none).
  bool? _uploadingBrokerCard;

  /// Picks a PDF / image (or photographs it) and uploads it to the private
  /// bucket — only this account and the Home8 team can open it.
  Future<void> _attach({required bool isBrokerCard}) async {
    if (_uploadingBrokerCard != null) return;
    final file = await MediaPicker.document(context);
    if (file == null || !mounted) return;
    setState(() => _uploadingBrokerCard = isBrokerCard);
    try {
      final stored = await AppScope.repositoryOf(context).uploadListingFile(
        kind: ListingFileKind.privateDoc,
        bytes: file.bytes,
        fileName: file.name,
        contentType: file.mimeType,
      );
      if (!mounted) return;
      setState(() {
        if (isBrokerCard) {
          _brokerCard = stored;
        } else {
          _tradeLicence = stored;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(e is RepositoryException
              ? e.message
              : "Couldn't upload. Try again."),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navDark,
        ));
    } finally {
      if (mounted) setState(() => _uploadingBrokerCard = null);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final profile = ListerProfile(
      type: _type,
      organisation: _organisation.text.trim(),
      licenceNumber: _licence.text.trim(),
      tradeLicence: _tradeLicence,
      brokerCard: _brokerCard,
    );

    try {
      final saved =
          await AppScope.repositoryOf(context).submitVerification(profile);
      if (!mounted) return;
      AppScope.authOf(context).setListerProfile(saved);
      _finish();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error;
      });
    }
  }

  void _finish() {
    final callback = widget.onDone;
    Navigator.of(context).pop();
    if (callback != null) callback();
  }

  @override
  Widget build(BuildContext context) {
    final licence = _tradeLicence;
    final card = _brokerCard;

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
                    AppSpacing.screenPadding, 8, AppSpacing.screenPadding, 20),
                children: [
                  Text(_type.verifyTitle,
                      style: AppTextStyles.display().copyWith(fontSize: 28)),
                  const SizedBox(height: 8),
                  Text(
                    'Required to earn the Verified-Agent badge and post '
                    'unlimited listings.',
                    style: AppTextStyles.body(color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 24),
                  FieldLabel(_type.organisationLabel),
                  const SizedBox(height: 8),
                  AppTextField(
                    controller: _organisation,
                    hint: 'e.g. Haus & Haus Realty',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  const FieldLabel('RERA / licence number'),
                  const SizedBox(height: 8),
                  AppTextField(
                    controller: _licence,
                    hint: 'e.g. 44921',
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  const FieldLabel('Trade licence'),
                  const SizedBox(height: 8),
                  if (licence == null)
                    DashedAddTile(
                      label: _uploadingBrokerCard == false
                          ? 'Uploading…'
                          : 'Upload trade licence (PDF or photo)',
                      icon: Icons.upload_file_rounded,
                      height: 78,
                      onTap: () => _attach(isBrokerCard: false),
                    )
                  else
                    UploadedRow(
                      fileName: licence.name,
                      statusLine: licence.statusLine,
                      actionLabel: 'Replace',
                      onAction: () => _attach(isBrokerCard: false),
                    ),
                  const SizedBox(height: 12),
                  if (card == null)
                    DashedAddTile(
                      label: _uploadingBrokerCard == true
                          ? 'Uploading…'
                          : 'Add broker card (optional)',
                      onTap: () => _attach(isBrokerCard: true),
                    )
                  else
                    UploadedRow(
                      fileName: card.name,
                      statusLine: card.statusLine,
                      icon: Icons.badge_outlined,
                      actionLabel: 'Replace',
                      onAction: () => _attach(isBrokerCard: true),
                    ),
                  const SizedBox(height: 20),
                  const InfoNote(
                    tone: NoteTone.warning,
                    message: 'Review takes up to 1 business day. You can '
                        'browse and save while pending, but listings stay in '
                        'draft until approved.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    InfoNote(
                      tone: NoteTone.warning,
                      icon: Icons.cloud_off_rounded,
                      message: "We couldn't send your documents. Check your "
                          'connection and try again.',
                      actionLabel: 'Retry',
                      onAction: _submit,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding, 4, AppSpacing.screenPadding, 12),
              child: Column(
                children: [
                  PrimaryButton(
                    label: 'Submit for verification',
                    loading: _submitting,
                    onTap: _canSubmit ? _submit : null,
                  ),
                  const SizedBox(height: 6),
                  // Skipping is allowed on purpose: a company that can't find
                  // its licence PDF right now should still reach the app, with
                  // its listings held in draft. Blocking here loses the account.
                  TertiaryButton(
                    label: "I'll do this later",
                    onTap: _submitting ? null : _finish,
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
