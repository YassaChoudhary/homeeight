import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../state/app_scope.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_icons.dart';
import '../widgets/home_nav_bar.dart';
import '../widgets/pill_button.dart';
import '../models/lister_profile.dart';
import '../models/my_listing.dart';
import '../state/listings_controller.dart';
import 'coming_soon_screen.dart';
import 'edit_profile_screen.dart';
import 'help_support_screen.dart';
import 'lister/my_listings_screen.dart';
import 'notifications_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';

/// Screen F01 / screen 30 — the account home, shown in the Login tab once a
/// session exists.
///
/// `MainShell` swaps between [LoginScreen] and this based on
/// `AuthController.isSignedIn`, so the tab keeps its slot in the nav bar and the
/// user never gets pushed onto a route they can't back out of.
///
/// ## Two menus, one screen
///
/// A buyer and a lister get different rows: the lister adds **My listings** and
/// **Post a reel**, and their header carries the stats strip and the ID /
/// trust badges. Which one you see is `AuthUser.isLister`.
///
/// This is one screen rather than two because everything except those two rows
/// and the header strip is identical — saved items, language, notifications,
/// help and log out behave the same for both. A second screen would be a copy
/// that drifts the first time one of those changes.
///
/// The stats are only fetched when the user is a lister; a buyer never pays for
/// a request whose numbers they'd never see.
class ProfileScreen extends StatefulWidget {
  final ValueChanged<NavTab> onNavTap;

  const ProfileScreen({super.key, required this.onNavTap});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AsyncController<ListerStats>? _stats;

  @override
  void initState() {
    super.initState();
    if (AppScope.authOf(context).user?.isLister ?? false) _startStats();
  }

  void _startStats() {
    _stats ??= AsyncController<ListerStats>(
      () => AppScope.repositoryOf(context).listerStats(),
    )..load();
  }

  @override
  void dispose() {
    _stats?.dispose();
    super.dispose();
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('Log out?', style: AppTextStyles.h2()),
        content: Text(
          'Your saved homes stay on this device until you log back in.',
          style: AppTextStyles.body(color: AppColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel',
                style: AppTextStyles.bodyStrong(color: AppColors.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Log out',
                style: AppTextStyles.bodyStrong(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      AppScope.authOf(context).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.authOf(context);

    return ColoredBox(
      color: AppColors.bg,
      child: ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          final user = auth.user;
          // MainShell only builds this when signed in, but a sign-out can land
          // one frame before the swap.
          if (user == null) return const SizedBox.shrink();

          // Someone can become a lister after this screen was first built —
          // by tapping + and completing screen 28 — so the fetch is started
          // here as well as in initState rather than only at construction.
          if (user.isLister) _startStats();

          return AppStateBuilder(
            builder: (context, appState) => ListView(
              padding: EdgeInsets.only(
                bottom: HomeNavBar.reservedSpace(context) + 16,
              ),
              children: [
                _ProfileHeader(
                  user: user,
                  city: appState.marketCity,
                  stats: _stats,
                  onEdit: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenPadding),
                  child: Column(
                    children: [
                      // --- Lister-only rows ---------------------------------
                      //
                      // These sit at the top because for a lister they're the
                      // reason to open this screen at all; Saved Items is a
                      // secondary concern once you're selling.
                      if (user.isLister) ...[
                        _MenuCard(
                          iconAsset: NavIcons.discover,
                          iconTint: AppColors.primary,
                          iconBg: AppColors.primaryTint,
                          label: 'My listings',
                          trailingText: _listingCount(),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const MyListingsScreen(),
                              ),
                            );
                            // The count in this row and the header strip go
                            // stale the moment a listing is posted or deleted.
                            if (context.mounted) _stats?.load();
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      _MenuCard(
                        iconAsset: AppIcons.heartSolid,
                        iconTint: AppColors.amber,
                        iconBg: const Color(0xFFFCE8C4),
                        label: 'Saved Items',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SavedScreen(),
                          ),
                        ),
                      ),
                      if (user.isLister) ...[
                        const SizedBox(height: 14),
                        _MenuCard(
                          iconAsset: NavIcons.reelsTab,
                          iconTint: const Color(0xFF7A5AF0),
                          iconBg: const Color(0xFFEDE8FD),
                          label: 'Post a reel',
                          // No reel composer exists and video needs Cloudflare
                          // Stream, which isn't set up. Named specifically so
                          // the placeholder says what's missing.
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ComingSoonScreen(
                                title: 'Posting a reel is under progress',
                                message:
                                    'Recording and uploading a property reel '
                                    'needs video hosting, which is still being '
                                    'set up. Your photos already appear in '
                                    'search and on the listing page.',
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _MenuCard(
                        iconAsset: AppIcons.globe,
                        iconTint: AppColors.primary,
                        iconBg: AppColors.primaryTint,
                        label: 'Language & market',
                        trailingText:
                            '${appState.language.code.toUpperCase()} · '
                            '${appState.market.label}',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _MenuCard(
                        icon: Icons.notifications_none_rounded,
                        iconTint: AppColors.inkMuted,
                        iconBg: const Color(0xFFEFF2F3),
                        label: 'Notifications',
                        // The toggle is a shortcut for "all push on/off"; the
                        // per-channel detail lives on the Notifications screen.
                        toggleValue: appState.pushEnabled,
                        onToggle: appState.setPushEnabled,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _MenuCard(
                        icon: Icons.help_outline_rounded,
                        iconTint: AppColors.inkMuted,
                        iconBg: const Color(0xFFEFF2F3),
                        label: 'Help & support',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const HelpSupportScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      _LogOutButton(onTap: () => _confirmSignOut(context)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Trailing count on the My listings row. Empty while loading rather than
  /// "0" — a zero that turns into a four a moment later reads as a bug.
  String? _listingCount() {
    final value = _stats?.state.valueOrNull;
    return value == null ? null : '${value.listings}';
  }
}

/// Dark rounded header with the avatar, name and member line.
///
/// A lister gets two extra bands: the verification badges under the name, and
/// the four-figure stats strip. A buyer's header is exactly what it was before
/// the seller side existed — the extras are additive, not a redesign.
class _ProfileHeader extends StatelessWidget {
  final AuthUser user;
  final String city;
  final VoidCallback onEdit;

  /// Null for a buyer, and null for a lister until the first fetch resolves.
  final AsyncController<ListerStats>? stats;

  const _ProfileHeader({
    required this.user,
    required this.city,
    required this.onEdit,
    this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final isLister = user.isLister;

    return Container(
      padding: EdgeInsets.only(
          top: topInset + 16, bottom: isLister ? 18 : 26, left: 20, right: 20),
      decoration: const BoxDecoration(
        color: AppColors.navDark,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ProfileAvatar(user: user, size: 84, showVerifiedBadge: true),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.display(color: Colors.white)
                          .copyWith(fontSize: 23),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.memberLine(city),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(color: Colors.white60)
                          .copyWith(fontSize: 13.5),
                    ),
                    if (isLister) ...[
                      const SizedBox(height: 8),
                      _BadgeStrip(user: user, stats: stats),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onEdit,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child:
                      Icon(Icons.edit_outlined, color: Colors.white70, size: 22),
                ),
              ),
            ],
          ),
          if (isLister && stats != null) ...[
            const SizedBox(height: 18),
            ListenableBuilder(
              listenable: stats!,
              builder: (context, _) => stats!.state.when(
                loading: () => const _StatsStripSkeleton(),
                // A failed stats call must not take the whole account screen
                // with it — the menu below is what the user came for. The
                // strip just collapses.
                error: (_) => const SizedBox.shrink(),
                data: (value) => _StatsStrip(stats: value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "ID VERIFIED" and "TRUST 92" under the name.
class _BadgeStrip extends StatelessWidget {
  final AuthUser user;
  final AsyncController<ListerStats>? stats;

  const _BadgeStrip({required this.user, this.stats});

  @override
  Widget build(BuildContext context) {
    final value = stats?.state.valueOrNull;
    final profile = user.listerProfile;

    final idVerified =
        value?.idVerified ?? (profile?.isVerified ?? user.phoneVerified);
    final trust = value?.trustScore ?? profile?.trustScore;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (idVerified)
          const _Badge(
            label: 'ID VERIFIED',
            bg: Color(0xFF1F5F63),
            fg: Color(0xFF7FE3DA),
          )
        else if (profile?.status == VerificationStatus.pending)
          // Pending is shown, not hidden. The seller submitted documents and
          // is waiting; silence here reads as the upload having failed.
          const _Badge(
            label: 'VERIFICATION PENDING',
            bg: Color(0xFF5C4620),
            fg: Color(0xFFF3C77B),
          ),
        if (trust != null)
          _Badge(
            label: 'TRUST $trust',
            bg: const Color(0xFF5C4620),
            fg: const Color(0xFFF3C77B),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.micro(color: fg)
            .copyWith(fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Saved · Listings · Viewings · Rating.
class _StatsStrip extends StatelessWidget {
  final ListerStats stats;

  const _StatsStrip({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCell(value: '${stats.saved}', label: 'Saved'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCell(value: '${stats.listings}', label: 'Listings'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCell(value: '${stats.viewings}', label: 'Viewings'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCell(
            value: stats.ratingLabel,
            label: 'Rating',
            // Amber, matching the star colour used on listing cards, so the
            // one figure that isn't a count reads as a different kind of thing.
            valueColor: AppColors.amber,
          ),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;

  const _StatCell({
    required this.value,
    required this.label,
    this.valueColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                AppTextStyles.display(color: valueColor).copyWith(fontSize: 20),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.micro(color: Colors.white60)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }
}

class _StatsStripSkeleton extends StatelessWidget {
  const _StatsStripSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: Container(
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
          ),
          if (i < 3) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

/// Circular avatar with the teal ring. Shared with the Edit profile screen, so
/// the ring geometry can't drift between the two.
class ProfileAvatar extends StatelessWidget {
  final AuthUser user;
  final double size;
  final bool showVerifiedBadge;
  final Widget? badge;

  const ProfileAvatar({
    super.key,
    required this.user,
    this.size = 84,
    this.showVerifiedBadge = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user.avatarUrl;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2.4),
            ),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE3E8E8),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarUrl == null
                  ? Center(
                      child: Text(
                        _initials(user.name),
                        style: AppTextStyles.h1(color: AppColors.inkMuted)
                            .copyWith(fontSize: size * 0.32),
                      ),
                    )
                  : Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      cacheWidth: (size * 3).round(),
                      errorBuilder: (_, _, _) => Center(
                        child: Text(
                          _initials(user.name),
                          style: AppTextStyles.h1(color: AppColors.inkMuted)
                              .copyWith(fontSize: size * 0.32),
                        ),
                      ),
                    ),
            ),
          ),
          if (showVerifiedBadge)
            Positioned(
              right: -2,
              bottom: 2,
              child: Container(
                width: size * 0.30,
                height: size * 0.30,
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.navDark, width: 2.2),
                ),
                child: Icon(Icons.check_rounded,
                    color: Colors.white, size: size * 0.17),
              ),
            ),
          if (badge != null) Positioned(right: -2, bottom: 0, child: badge!),
        ],
      ),
    );
  }

  /// Falls back to initials rather than a generic person glyph — an avatar with
  /// your initials reads as "yours" even before you upload a photo.
  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// One white row in the account menu. Handles three trailing variants: chevron,
/// value + chevron, and a switch.
class _MenuCard extends StatelessWidget {
  final IconData? icon;
  final String? iconAsset;
  final Color iconTint;
  final Color iconBg;
  final String label;
  final String? trailingText;
  final bool? toggleValue;
  final ValueChanged<bool>? onToggle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.label,
    required this.iconTint,
    required this.iconBg,
    required this.onTap,
    this.icon,
    this.iconAsset,
    this.trailingText,
    this.toggleValue,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isToggle = toggleValue != null;

    return Pressable(
      // A row whose only action is its switch shouldn't also navigate on tap.
      onTap: isToggle ? null : onTap,
      child: Container(
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              padding: const EdgeInsets.all(14),
              child: iconAsset != null
                  ? SvgPicture.asset(
                      iconAsset!,
                      colorFilter: ColorFilter.mode(iconTint, BlendMode.srcIn),
                    )
                  : Icon(icon, color: iconTint, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyStrong().copyWith(fontSize: 17),
              ),
            ),
            if (trailingText != null) ...[
              Text(trailingText!, style: AppTextStyles.caption()),
              const SizedBox(width: 8),
            ],
            if (isToggle)
              AppSwitch(value: toggleValue!, onChanged: onToggle)
            else
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.inkMuted, size: 24),
          ],
        ),
      ),
    );
  }
}

class _LogOutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogOutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
            const SizedBox(width: 10),
            Text('Log out',
                style: AppTextStyles.bodyStrong(color: AppColors.danger)
                    .copyWith(fontSize: 17)),
          ],
        ),
      ),
    );
  }
}
