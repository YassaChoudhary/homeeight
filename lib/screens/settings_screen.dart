import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../state/app_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icons.dart';
import '../widgets/pill_button.dart';
import 'notifications_screen.dart';
import 'help_support_screen.dart';

/// Screen F05 — "Settings".
///
/// Rows are grouped into three cards with hairline dividers *between* rows but
/// not at the card edges, which is what the frame shows and what
/// `ListTile.divideTiles` gets wrong.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _notYet(BuildContext context, String what) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            SettingsHeader(title: 'Settings'),
            Expanded(
              child: AppStateBuilder(
                builder: (context, state) => ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding, 6, AppSpacing.screenPadding, 28),
                  children: [
                    SettingsCard(
                      rows: [
                        SettingsRow(
                          iconAsset: AppIcons.globe,
                          label: 'Language',
                          value: state.language.label.split(' ').last,
                          onTap: () => CurrencyRegionSheet.show(context),
                        ),
                        SettingsRow(
                          icon: Icons.location_on_outlined,
                          label: 'Market',
                          value: state.market.label,
                          onTap: () => CurrencyRegionSheet.show(context),
                        ),
                        SettingsRow(
                          icon: Icons.attach_money_rounded,
                          label: 'Currency',
                          value: state.currency,
                          onTap: () => CurrencyRegionSheet.show(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SettingsCard(
                      rows: [
                        SettingsRow(
                          icon: Icons.dark_mode_outlined,
                          iconTint: AppColors.inkMuted,
                          label: 'Dark theme',
                          // Stores the preference only — there is no dark
                          // palette yet. See AppState.setDarkTheme.
                          toggleValue: state.darkTheme,
                          onToggle: (v) {
                            state.setDarkTheme(v);
                            if (v) _notYet(context, 'Dark theme');
                          },
                        ),
                        SettingsRow(
                          icon: Icons.notifications_none_rounded,
                          iconTint: AppColors.inkMuted,
                          label: 'Notifications',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const NotificationsScreen(),
                            ),
                          ),
                        ),
                        SettingsRow(
                          icon: Icons.lock_outline_rounded,
                          iconTint: AppColors.inkMuted,
                          label: 'Privacy',
                          onTap: () => _notYet(context, 'Privacy settings'),
                        ),
                        SettingsRow(
                          icon: Icons.person_off_outlined,
                          iconTint: AppColors.inkMuted,
                          label: 'Blocked users',
                          value: '2',
                          onTap: () => _notYet(context, 'Blocked users'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SettingsCard(
                      rows: [
                        SettingsRow(
                          icon: Icons.help_outline_rounded,
                          iconTint: AppColors.inkMuted,
                          label: 'Help & support',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const HelpSupportScreen(),
                            ),
                          ),
                        ),
                        SettingsRow(
                          icon: Icons.description_outlined,
                          iconTint: AppColors.inkMuted,
                          label: 'Terms & privacy policy',
                          onTap: () => _notYet(context, 'Terms & privacy'),
                        ),
                        SettingsRow(
                          icon: Icons.info_outline_rounded,
                          iconTint: AppColors.inkMuted,
                          label: 'About Home8',
                          // Matches pubspec `version:`. Bump both together.
                          value: 'v1.0.0',
                          onTap: () => _notYet(context, 'About'),
                        ),
                      ],
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

// ---------------------------------------------------------------------------
// Shared settings chrome — reused by Notifications and Help & support
// ---------------------------------------------------------------------------

/// Centred title with a back arrow and a balancing gap on the right.
class SettingsHeader extends StatelessWidget {
  final String title;
  const SettingsHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.arrow_back_rounded,
                  color: AppColors.ink, size: 24),
            ),
          ),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                style: AppTextStyles.h1().copyWith(fontSize: 22)),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// White card holding settings rows, with dividers only between them.
class SettingsCard extends StatelessWidget {
  final List<Widget> rows;
  const SettingsCard({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFEDF1F1),
                indent: 18,
                endIndent: 18,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One settings row. Trailing is a switch, a value + chevron, or a chevron.
class SettingsRow extends StatelessWidget {
  final IconData? icon;
  final String? iconAsset;
  final Color iconTint;
  final String label;
  final String? value;
  final String? subtitle;
  final bool? toggleValue;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;

  const SettingsRow({
    super.key,
    required this.label,
    this.icon,
    this.iconAsset,
    this.iconTint = AppColors.primary,
    this.value,
    this.subtitle,
    this.toggleValue,
    this.onToggle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isToggle = toggleValue != null;
    final hasIcon = icon != null || iconAsset != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isToggle ? null : onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            if (hasIcon) ...[
              SizedBox(
                width: 24,
                height: 24,
                child: iconAsset != null
                    ? SvgPicture.asset(
                        iconAsset!,
                        colorFilter:
                            ColorFilter.mode(iconTint, BlendMode.srcIn),
                      )
                    : Icon(icon, color: iconTint, size: 22),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyStrong().copyWith(fontSize: 16.5),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption()),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              Text(value!, style: AppTextStyles.caption().copyWith(fontSize: 14)),
              const SizedBox(width: 8),
            ],
            if (isToggle)
              AppSwitch(value: toggleValue!, onChanged: onToggle)
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.inkMuted, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Teal pill switch. Wraps Material's `Switch` rather than reimplementing the
/// gesture, so drag, semantics and reduced-motion keep working.
class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1.05,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.primary,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: const Color(0xFFCFD9DA),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// F06 — Currency & region sheet
// ---------------------------------------------------------------------------

/// Screen F06. Edits a local draft and commits both values on Apply, so
/// half-changing your mind and dismissing leaves nothing behind.
class CurrencyRegionSheet extends StatefulWidget {
  const CurrencyRegionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const CurrencyRegionSheet(),
    );
  }

  @override
  State<CurrencyRegionSheet> createState() => _CurrencyRegionSheetState();
}

class _CurrencyRegionSheetState extends State<CurrencyRegionSheet> {
  static const List<(String, String)> _currencies = [
    ('AED', 'UAE Dirham'),
    ('SAR', 'Saudi Riyal'),
    ('PKR', 'Pak Rupee'),
    ('USD', 'US Dollar'),
    ('GBP', 'UK Pound'),
    ('EUR', 'Euro'),
  ];

  String? _currency;
  Market? _market;

  @override
  void initState() {
    super.initState();
    final state = AppScope.of(context).appState;
    _currency = state.currency;
    _market = state.market;
  }

  void _apply() {
    final state = AppScope.of(context).appState;
    final market = _market;
    if (market != null) state.setMarket(market);
    // Order matters: setMarket clears the currency override, so the explicit
    // currency has to be written after it.
    state.setCurrency(_currency);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg + 8),
          topRight: Radius.circular(AppRadius.lg + 8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('Currency & region',
                    style: AppTextStyles.display().copyWith(fontSize: 24)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                children: [
                  _SectionLabel('DISPLAY CURRENCY'),
                  const SizedBox(height: 10),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.5,
                    children: [
                      for (final (code, name) in _currencies)
                        _ChoiceTile(
                          selected: _currency == code,
                          onTap: () => setState(() => _currency = code),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(code,
                                  style: AppTextStyles.bodyStrong()
                                      .copyWith(fontSize: 17)),
                              const SizedBox(height: 2),
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption()
                                      .copyWith(fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _SectionLabel('MARKET'),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.zero,
                      itemCount: Market.values.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final m = Market.values[i];
                        return SizedBox(
                          width: 108,
                          child: _ChoiceTile(
                            selected: _market == m,
                            onTap: () => setState(() => _market = m),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(m.flagAsset,
                                    height: 28, cacheWidth: 120),
                                const SizedBox(height: 8),
                                Text(m.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.bodyStrong()
                                        .copyWith(fontSize: 14)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF3E4),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 18, color: AppColors.warning),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Prices convert at daily mid-market rates. '
                            "Contracts always settle in the listing's market "
                            'currency.',
                            style: AppTextStyles.caption(color: AppColors.ink)
                                .copyWith(fontSize: 13.5, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: PrimaryButton(label: 'Apply', onTap: _apply),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.micro(color: AppColors.inkMuted)
          .copyWith(fontSize: 12.5, letterSpacing: 0.7),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _ChoiceTile({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTint : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.line,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}
