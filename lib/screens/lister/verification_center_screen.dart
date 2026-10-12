import 'package:flutter/material.dart';

import '../../core/async_value.dart';
import '../../models/lister_profile.dart';
import '../../state/app_scope.dart';
import '../../state/listings_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/state_views.dart';
import 'lister_gate.dart';
import 'verification_required_screen.dart';

/// Verification center — where a seller sees whether their account is
/// in review, approved or needs changes, read live from the server.
class VerificationCenterScreen extends StatefulWidget {
  const VerificationCenterScreen({super.key});

  @override
  State<VerificationCenterScreen> createState() =>
      _VerificationCenterScreenState();
}

class _VerificationCenterScreenState extends State<VerificationCenterScreen> {
  late final AsyncController<ListerProfile?> _status;

  @override
  void initState() {
    super.initState();
    _status = AsyncController<ListerProfile?>(() async {
      final repo = AppScope.repositoryOf(context);
      final auth = AppScope.authOf(context);
      final server = await repo.myVerification();
      // Keep the app's cached status in step (profile badge etc.).
      final cached = auth.user?.listerProfile;
      if (server != null &&
          (cached?.status != server.status || cached?.type != server.type)) {
        auth.setListerProfile((cached ?? server).copyWith(
          type: server.type,
          status: server.status,
          reviewNote: server.reviewNote,
        ));
      }
      return server;
    })
      ..load();
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  Future<void> _startVerification(ListerProfile? current) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerificationRequiredScreen(
          initialType: current?.type,
          rejectionNote: current?.status == VerificationStatus.rejected
              ? current!.reviewNote
              : '',
        ),
      ),
    );
    if (mounted) _status.load();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // Dark rounded header, same as My Listings.
          Container(
            padding: EdgeInsets.only(top: topInset + 4, bottom: 22),
            decoration: const BoxDecoration(
              color: AppColors.navDark,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
                Expanded(
                  child: Text('Verification center',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.h1(color: Colors.white)),
                ),
                const SizedBox(width: 52),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _status,
              builder: (context, _) => _status.state.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_) => Center(
                  child: ErrorStateView(
                    message: "Couldn't load your verification status.",
                    onRetry: _status.load,
                  ),
                ),
                data: (profile) => RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _status.load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding,
                        20, AppSpacing.screenPadding, 32),
                    children: [
                      _StatusCard(profile: profile),
                      const SizedBox(height: 16),
                      _Timeline(status: profile?.status ?? VerificationStatus.none),
                      if (profile != null) ...[
                        const SizedBox(height: 16),
                        _DetailsCard(profile: profile),
                      ],
                      const SizedBox(height: 24),
                      ..._actions(profile),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actions(ListerProfile? profile) {
    final status = profile?.status ?? VerificationStatus.none;
    return switch (status) {
      VerificationStatus.none => [
          PrimaryButton(
            label: 'Start verification',
            onTap: () => _startVerification(profile),
          ),
        ],
      VerificationStatus.rejected => [
          PrimaryButton(
            label: 'Submit again',
            onTap: () => _startVerification(profile),
          ),
        ],
      VerificationStatus.verified => [
          PrimaryButton(
            label: 'Post a listing',
            leadingIcon: Icons.add_rounded,
            onTap: () => startListing(context),
          ),
        ],
      VerificationStatus.pending => [
          Center(
            child: Text('Pull down to refresh the status.',
                style: AppTextStyles.caption()),
          ),
        ],
    };
  }
}

/// The big status card at the top.
class _StatusCard extends StatelessWidget {
  final ListerProfile? profile;
  const _StatusCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final status = profile?.status ?? VerificationStatus.none;
    final (Color tint, Color bg, IconData icon, String badge, String title,
        String body) = switch (status) {
      VerificationStatus.pending => (
          AppColors.amber,
          const Color(0xFFFCEBD2),
          Icons.hourglass_top_rounded,
          'IN REVIEW',
          'Your account is under review',
          "We're checking your documents. This usually takes up to 1 "
              "business day. You'll be able to post listings once approved.",
        ),
      VerificationStatus.verified => (
          AppColors.success,
          const Color(0xFFE3F4EA),
          Icons.verified_rounded,
          'APPROVED',
          'Your account is verified',
          'You can post listings, and they show the Verified badge to buyers.',
        ),
      VerificationStatus.rejected => (
          AppColors.danger,
          const Color(0xFFFBE0DC),
          Icons.error_outline_rounded,
          'NEEDS CHANGES',
          'We couldn\'t approve your account',
          (profile?.reviewNote.isNotEmpty ?? false)
              ? 'Reason: ${profile!.reviewNote}. Please fix it and submit again.'
              : 'Please check your documents and submit again.',
        ),
      VerificationStatus.none => (
          AppColors.primary,
          AppColors.primaryTint,
          Icons.shield_outlined,
          'NOT VERIFIED',
          'Verify your account',
          'Only verified individuals, agents and companies can post '
              'listings on Home8.',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg + 4),
        border: Border.all(color: tint.withValues(alpha: 0.35), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, color: tint, size: 28),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(badge,
                    style: AppTextStyles.micro(color: Colors.white).copyWith(
                        fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: AppTextStyles.h2().copyWith(fontSize: 20)),
          const SizedBox(height: 6),
          Text(body,
              style: AppTextStyles.body(color: AppColors.inkMuted)
                  .copyWith(fontSize: 14.5, height: 21 / 14.5)),
        ],
      ),
    );
  }
}

/// Submitted → In review → Approved.
class _Timeline extends StatelessWidget {
  final VerificationStatus status;
  const _Timeline({required this.status});

  @override
  Widget build(BuildContext context) {
    final submitted = status != VerificationStatus.none;
    final reviewed = status == VerificationStatus.verified ||
        status == VerificationStatus.rejected;
    final steps = <(String, String, bool, bool)>[
      // (label, caption, done, current)
      ('Documents submitted', 'Your details and files', submitted, !submitted),
      (
        'Under review',
        'Home8 team checks your documents',
        reviewed,
        status == VerificationStatus.pending,
      ),
      (
        status == VerificationStatus.rejected ? 'Needs changes' : 'Approved',
        status == VerificationStatus.rejected
            ? 'Fix and submit again'
            : 'Post listings with the Verified badge',
        status == VerificationStatus.verified,
        status == VerificationStatus.rejected,
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg + 4),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            _TimelineRow(
              label: steps[i].$1,
              caption: steps[i].$2,
              done: steps[i].$3,
              current: steps[i].$4,
              failed: i == 2 && status == VerificationStatus.rejected,
              last: i == steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final String label;
  final String caption;
  final bool done;
  final bool current;
  final bool failed;
  final bool last;

  const _TimelineRow({
    required this.label,
    required this.caption,
    required this.done,
    required this.current,
    required this.failed,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final Color dot = failed
        ? AppColors.danger
        : done
            ? AppColors.success
            : current
                ? AppColors.amber
                : AppColors.line;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done || failed ? dot : Colors.transparent,
                  border: Border.all(color: dot, width: 2),
                ),
                child: done
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: Colors.white)
                    : failed
                        ? const Icon(Icons.close_rounded,
                            size: 16, color: Colors.white)
                        : current
                            ? Center(
                                child: Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                      color: dot, shape: BoxShape.circle),
                                ),
                              )
                            : null,
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: done ? AppColors.success : AppColors.line,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTextStyles.bodyStrong(
                        color: done || current || failed
                            ? AppColors.ink
                            : AppColors.inkMuted,
                      ).copyWith(fontSize: 15.5)),
                  const SizedBox(height: 2),
                  Text(caption, style: AppTextStyles.caption()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What was submitted.
class _DetailsCard extends StatelessWidget {
  final ListerProfile profile;
  const _DetailsCard({required this.profile});

  static String _date(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final individual = profile.type == ListerType.individual;
    final rows = <(String, String)>[
      ('Account type', profile.type.label),
      if (individual && profile.legalName.isNotEmpty)
        ('Legal name', profile.legalName),
      if (!individual && profile.organisation.isNotEmpty)
        (profile.type.organisationLabel, profile.organisation),
      if (!individual && profile.licenceNumber.isNotEmpty)
        ('RERA / licence no.', profile.licenceNumber),
      ('Documents', individual ? 'ID card (front & back)' : 'Trade licence'),
      if (profile.submittedAt != null)
        ('Submitted', _date(profile.submittedAt!)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg + 4),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Text(rows[i].$1, style: AppTextStyles.caption()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyStrong().copyWith(fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
