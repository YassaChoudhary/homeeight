import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_scope.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/pill_button.dart';
import 'email_login_screen.dart';
import 'purpose_screen.dart';

/// Screen 25 — "Enter your code".
///
/// ## How the six boxes work
///
/// There is **one** hidden `TextField` behind six painted boxes, not six fields.
/// Six real fields means six focus nodes, manual backspace handling, and broken
/// SMS autofill; one field with `autofillHints: [oneTimeCode]` lets the OS fill
/// all six at once and gets caret and paste behaviour for free. The boxes are
/// just a painted view of `_controller.text`.
///
/// With Firebase on, the code is checked by the Supabase Edge Function
/// `email-auth`; a wrong, expired or locked-out code shows the server's message
/// ("That code isn't right. 3 attempts left.") and clears the boxes. In local
/// mode any six digits pass.
class OtpScreen extends StatefulWidget {
  final VoidCallback? onSignedIn;

  const OtpScreen({super.key, this.onSignedIn});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const int _length = 6;
  /// Matches the server's 30-second gap between emails (supabase/migrations/20261011010000_email_otp.sql), so
  /// "Resend code" never appears before the server would accept it.
  static const int _resendSeconds = 30;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  Timer? _timer;
  int _secondsLeft = _resendSeconds;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  String get _code => _controller.text;
  bool get _complete => _code.length == _length;

  String get _timerLabel {
    final m = _secondsLeft ~/ 60;
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _verify() async {
    final auth = AppScope.authOf(context);
    if (auth.busy) return;
    setState(() => _error = null);

    String? failure;
    try {
      final ok = await auth.verifyCode(_code);
      if (!ok) failure = "That code doesn't look right. Try again.";
    } on AuthException catch (e) {
      failure = e.message;
    }
    if (!mounted) return;

    if (failure != null) {
      // Clear the boxes so the next attempt starts clean.
      _controller.clear();
      setState(() => _error = failure);
      _focus.requestFocus();
      return;
    }
    // New accounts get "What brings you to Home8?"; returning users go in.
    continueAfterSignIn(context, widget.onSignedIn);
  }

  Future<void> _resend() async {
    final auth = AppScope.authOf(context);
    if (auth.busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _error = null);
    try {
      await auth.resendCode();
      if (!mounted) return;
      _controller.clear();
      _startTimer();
      messenger.showSnackBar(
        SnackBar(content: Text('New code sent to ${auth.maskedTarget}.')),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _onChanged(String value) {
    setState(() => _error = null);
    // Auto-submit the moment the sixth digit lands, which is what people
    // expect from an SMS code and saves a tap after autofill.
    if (value.length == _length) {
      _focus.unfocus();
      _verify();
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
          builder: (context, _) => Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding,
                      12, AppSpacing.screenPadding, 20),
                  children: [
                    const AuthBackButton(),
                    const SizedBox(height: 20),
                    Text('Enter your code',
                        style: AppTextStyles.display().copyWith(fontSize: 27)),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        style: AppTextStyles.body(color: AppColors.inkMuted),
                        children: [
                          const TextSpan(text: 'We sent a 6-digit code to '),
                          TextSpan(
                            text: auth.maskedTarget,
                            style: AppTextStyles.bodyStrong(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _CodeBoxes(
                      length: _length,
                      code: _code,
                      focusNode: _focus,
                      controller: _controller,
                      hasError: _error != null,
                      onChanged: _onChanged,
                      onTap: () => _focus.requestFocus(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: AppTextStyles.caption(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _secondsLeft > 0
                              ? Text.rich(
                                  TextSpan(
                                    style: AppTextStyles.body(
                                        color: AppColors.inkMuted),
                                    children: [
                                      const TextSpan(text: 'Resend in '),
                                      TextSpan(
                                        text: _timerLabel,
                                        style: AppTextStyles.bodyStrong(),
                                      ),
                                    ],
                                  ),
                                )
                              : GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _resend,
                                  child: Text(
                                    'Resend code',
                                    style: AppTextStyles.bodyStrong(
                                        color: AppColors.primary),
                                  ),
                                ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).maybePop(),
                          child: Text(
                            auth.pendingEmail != null
                                ? 'Change email'
                                : 'Change number',
                            style: AppTextStyles.bodyStrong().copyWith(
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, 0,
                    AppSpacing.screenPadding, 12),
                child: PrimaryButton(
                  label: 'Verify & continue',
                  loading: auth.busy,
                  onTap: _complete ? _verify : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Six painted boxes over one hidden field. See the class doc on [OtpScreen]
/// for why it's built this way.
class _CodeBoxes extends StatelessWidget {
  final int length;
  final String code;
  final FocusNode focusNode;
  final TextEditingController controller;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;

  const _CodeBoxes({
    required this.length,
    required this.code,
    required this.focusNode,
    required this.controller,
    required this.hasError,
    required this.onChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The real input, held offstage but focusable. Opacity 0 rather than
        // Offstage/Visibility because those detach it from the tree and the
        // keyboard closes.
        SizedBox(
          height: 1,
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: length,
              onChanged: onChanged,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            children: [
              for (var i = 0; i < length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _CodeBox(
                    char: i < code.length ? code[i] : '',
                    filled: i < code.length,
                    // The next empty box shows the caret.
                    active: i == code.length && focusNode.hasFocus,
                    hasError: hasError,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  final String char;
  final bool filled;
  final bool active;
  final bool hasError;

  const _CodeBox({
    required this.char,
    required this.filled,
    required this.active,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    final Color border = hasError
        ? AppColors.danger
        : active
            ? AppColors.ink
            : filled
                ? AppColors.primary
                : AppColors.line;

    return AspectRatio(
      aspectRatio: 0.84,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: border, width: active ? 2 : 1.4),
        ),
        child: filled
            ? Text(char,
                style: AppTextStyles.display()
                    .copyWith(fontSize: 24, fontWeight: FontWeight.w700))
            : active
                ? const _Caret()
                : const SizedBox.shrink(),
      ),
    );
  }
}

/// Blinking caret in the active box.
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        // Square wave rather than a fade — a caret blinks, it doesn't pulse.
        opacity: _c.value < 0.5 ? 1 : 0,
        child: Container(width: 2, height: 26, color: AppColors.ink),
      ),
    );
  }
}
