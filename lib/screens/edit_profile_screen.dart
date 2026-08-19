import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/pill_button.dart';
import 'profile_screen.dart';

/// Screen F04 — "Edit profile".
///
/// Edits a local copy and only writes to [AuthController] on Save, so backing
/// out discards changes. The verification chips are **status, not actions you
/// can fake** — "Verified" is flat text, "Confirm" is a button, because one is a
/// fact and the other is a request the backend has to fulfil.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final user = AppScope.authOf(context).user;
    _name = TextEditingController(text: user?.name ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
    _email = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _save() {
    AppScope.authOf(context).updateProfile(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
    );
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile updated'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navDark,
      ),
    );
  }

  void _notYet(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$what is work in progress — coming soon.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navDark,
        ),
      );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('Delete account?', style: AppTextStyles.h2()),
        content: Text(
          'This removes your profile, saved homes and chats. It cannot be '
          'undone.',
          style: AppTextStyles.body(color: AppColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep account',
                style: AppTextStyles.bodyStrong(color: AppColors.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete',
                style: AppTextStyles.bodyStrong(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _notYet('Account deletion');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.authOf(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            final user = auth.user;
            if (user == null) return const SizedBox.shrink();

            return Column(
              children: [
                _EditHeader(
                  canSave: _dirty,
                  onBack: () => Navigator.of(context).maybePop(),
                  onSave: _save,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding, 6, AppSpacing.screenPadding, 24),
                    children: [
                      Center(
                        child: Column(
                          children: [
                            ProfileAvatar(
                              user: user,
                              size: 108,
                              badge: _CameraBadge(
                                onTap: () => _notYet('Photo upload'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _notYet('Photo upload'),
                              child: Text(
                                'Change photo',
                                style: AppTextStyles.bodyStrong(
                                    color: AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _Field(
                        label: 'Full name',
                        controller: _name,
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: 18),
                      _Field(
                        label: 'Phone',
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => _markDirty(),
                        trailing: user.phoneVerified
                            ? const _StatusChip(
                                label: 'Verified',
                                bg: Color(0xFFE7F4EC),
                                fg: AppColors.success,
                                icon: Icons.check_rounded,
                              )
                            : _ActionChip(
                                label: 'Verify',
                                onTap: () => _notYet('Phone verification'),
                              ),
                      ),
                      const SizedBox(height: 18),
                      _Field(
                        label: 'Email',
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) => _markDirty(),
                        trailing: user.emailVerified
                            ? const _StatusChip(
                                label: 'Verified',
                                bg: Color(0xFFE7F4EC),
                                fg: AppColors.success,
                                icon: Icons.check_rounded,
                              )
                            : _ActionChip(
                                label: 'Confirm',
                                bg: const Color(0xFFFCEBD2),
                                fg: AppColors.warning,
                                onTap: () => _notYet('Email confirmation'),
                              ),
                      ),
                      const SizedBox(height: 18),
                      _PasswordRow(onChange: () => _notYet('Password change')),
                      const SizedBox(height: 18),
                      _AccountTypeRow(
                        type: user.intent == UserIntent.listProperty
                            ? 'Agent'
                            : 'Individual',
                        onBecomeAgent: () => _notYet('Agent onboarding'),
                      ),
                      const SizedBox(height: 40),
                      Center(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _confirmDelete,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              'Delete account',
                              style: AppTextStyles.bodyStrong(
                                  color: AppColors.danger),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EditHeader extends StatelessWidget {
  final bool canSave;
  final VoidCallback onBack;
  final VoidCallback onSave;

  const _EditHeader({
    required this.canSave,
    required this.onBack,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.arrow_back_rounded,
                  color: AppColors.ink, size: 24),
            ),
          ),
          Expanded(
            child: Text('Edit profile',
                textAlign: TextAlign.center,
                style: AppTextStyles.h1().copyWith(fontSize: 22)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canSave ? onSave : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Save',
                style: AppTextStyles.bodyStrong(
                  // Greyed until something actually changed, so the button
                  // tells you whether you have unsaved edits.
                  color: canSave ? AppColors.primary : AppColors.inkMuted,
                ).copyWith(fontSize: 16.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraBadge extends StatelessWidget {
  final VoidCallback onTap;
  const _CameraBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.bg, width: 2.5),
        ),
        child: const Icon(Icons.photo_camera_rounded,
            color: Colors.white, size: 18),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;
  final Widget? trailing;

  const _Field({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.keyboardType,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.bodyStrong().copyWith(fontSize: 15.5)),
        const SizedBox(height: 8),
        Container(
          height: 64,
          padding: const EdgeInsetsDirectional.only(start: 18, end: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  onChanged: onChanged,
                  style: AppTextStyles.bodyStrong().copyWith(fontSize: 16.5),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ],
    );
  }
}

/// Non-interactive state, e.g. "Verified".
class _StatusChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final IconData? icon;

  const _StatusChip({
    required this.label,
    required this.bg,
    required this.fg,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: AppTextStyles.micro(color: fg)
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Tappable chip that requests something from the backend.
class _ActionChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.onTap,
    this.bg = const Color(0xFFFCEBD2),
    this.fg = AppColors.warning,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: AppTextStyles.micro(color: fg)
                .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _PasswordRow extends StatelessWidget {
  final VoidCallback onChange;
  const _PasswordRow({required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Password',
            style: AppTextStyles.bodyStrong().copyWith(fontSize: 15.5)),
        const SizedBox(height: 8),
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    for (var i = 0; i < 8; i++)
                      Container(
                        margin: const EdgeInsetsDirectional.only(end: 7),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.inkMuted,
                        ),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onChange,
                child: Text('Change',
                    style: AppTextStyles.bodyStrong(color: AppColors.primary)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountTypeRow extends StatelessWidget {
  final String type;
  final VoidCallback onBecomeAgent;

  const _AccountTypeRow({required this.type, required this.onBecomeAgent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Account type',
                    style: AppTextStyles.bodyStrong().copyWith(fontSize: 16.5)),
                const SizedBox(height: 2),
                Text(type, style: AppTextStyles.caption()),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBecomeAgent,
            child: Text('Become an agent',
                style: AppTextStyles.bodyStrong(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
