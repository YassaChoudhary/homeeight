import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Destinations reachable from the shell.
///
/// Only four appear in the bar, in this order:
///   Discover · Reels · [ + ] · Search · Chats
///
/// [profile] is a real tab in the stack but has no slot in the bar — it's
/// reached from the avatar in the Home hero. Keeping it a tab (rather than a
/// pushed route) means the bar stays put and Back never strands the user.
///
/// The centre button is NOT a destination any more. It used to be Home; it is
/// now the "post a listing" action, which is why it shows a `+` and why it is
/// surfaced through [HomeNavBar.onPost] instead of through this enum.
enum NavTab { discover, reels, search, chats, profile }

class NavIcons {
  NavIcons._();

  // --- Bottom nav ----------------------------------------------------------
  /// House outline — the Discover tab.
  static const String discover = 'assets/icons/discover_home.svg';

  /// Two offset rounded cards — the Reels tab.
  ///
  /// Note: the original Figma export shipped this glyph under the name
  /// `bookmark.svg`, and the bookmark ribbon under `reels.svg`. Both constants
  /// point at the file holding the correct artwork; if the assets are ever
  /// renamed, this class is the only place to edit.
  static const String reelsTab = 'assets/icons/bookmark.svg';

  static const String search = 'assets/icons/search.svg';
  static const String chats = 'assets/icons/chat_bubble.svg';

  /// Plus — the raised centre button (post a listing).
  static const String post = 'assets/icons/post_plus.svg';

  /// Filled circular avatar — the account entry point in the Home hero.
  static const String profileAvatar = 'assets/icons/profile_avatar.svg';

  // --- Elsewhere -----------------------------------------------------------
  /// Bookmark ribbon — the save action on the reel's right rail.
  static const String reelSave = 'assets/icons/reels.svg';

  static const String profile = 'assets/icons/person.svg';
  static const String home = 'assets/icons/home.svg';
  static const String heart = 'assets/icons/heart.svg';
  static const String comment = 'assets/icons/comment.svg';
  static const String locationPin = 'assets/icons/location_pin.svg';

  /// House-with-key and building glyphs, used by the For Rent / For Sale
  /// toggle on Home.
  static const String purposeRent = 'assets/icons/purpose_rent.svg';
  static const String purposeSale = 'assets/icons/purpose_sale.svg';
}

/// Floating dark pill nav with a raised centre button.
///
/// Geometry from the Figma frames: 58pt bar, 16pt side inset, and a 66pt centre
/// button whose white ring breaks the bar's top edge by 13pt with a teal glow
/// beneath.
class HomeNavBar extends StatelessWidget {
  static const double barHeight = 58;
  static const double sideInset = 16;
  static const double bottomGap = 12;
  static const double centerSize = 66;
  static const double overhang = 13;

  static const Color activeColor = Color(0xFF3FD6C8);
  static const Color inactiveColor = Color(0xFF8B94A5);
  static const Color badgeColor = Color(0xFFF5A623);

  /// Vertical space a scrolling screen must leave free at the bottom so its
  /// content never disappears behind the floating bar.
  static double reservedSpace(BuildContext context) =>
      barHeight + overhang + bottomGap + MediaQuery.of(context).padding.bottom;

  final NavTab current;
  final ValueChanged<NavTab> onTap;

  /// Fired by the raised centre `+`. Separate from [onTap] because posting is
  /// an action, not a destination — it opens a flow over the current tab and
  /// leaves the selected tab untouched.
  final VoidCallback? onPost;

  /// Unread chat count. Zero hides the badge entirely.
  ///
  /// Defaults to 0 because there is no chat backend — a hardcoded number reads
  /// as real unread messages sitting behind a screen that doesn't exist. Wire
  /// this to the real count when messaging lands.
  final int chatBadge;

  const HomeNavBar({
    super.key,
    required this.current,
    required this.onTap,
    this.onPost,
    this.chatBadge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final barBottom = bottomGap + safeBottom;

    return SizedBox(
      height: barHeight + overhang + bottomGap + safeBottom,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: sideInset,
            right: sideInset,
            bottom: barBottom,
            height: barHeight,
            child: RepaintBoundary(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.navDark,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.26),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _NavItem(
                      label: 'Discover',
                      icon: NavIcons.discover,
                      active: current == NavTab.discover,
                      onTap: () => onTap(NavTab.discover),
                    ),
                    _NavItem(
                      label: 'Reels',
                      icon: NavIcons.reelsTab,
                      active: current == NavTab.reels,
                      onTap: () => onTap(NavTab.reels),
                    ),
                    // Reserved slot beneath the raised centre button.
                    const Expanded(child: SizedBox.shrink()),
                    _NavItem(
                      label: 'Search',
                      icon: NavIcons.search,
                      active: current == NavTab.search,
                      onTap: () => onTap(NavTab.search),
                    ),
                    _NavItem(
                      label: 'Chats',
                      icon: NavIcons.chats,
                      active: current == NavTab.chats,
                      badge: chatBadge,
                      onTap: () => onTap(NavTab.chats),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: barBottom + barHeight - (centerSize - overhang),
            height: centerSize,
            child: Center(child: _PostButton(onTap: onPost)),
          ),
        ],
      ),
    );
  }
}

class _PostButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _PostButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Post a listing',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: RepaintBoundary(
          child: Container(
            width: HomeNavBar.centerSize,
            height: HomeNavBar.centerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(4),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
              padding: const EdgeInsets.all(17),
              child: SvgPicture.asset(
                NavIcons.post,
                colorFilter:
                    const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final String icon;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? HomeNavBar.activeColor : HomeNavBar.inactiveColor;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(
                    width: 23,
                    height: 23,
                    child: SvgPicture.asset(
                      icon,
                      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -11,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: HomeNavBar.badgeColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        constraints: const BoxConstraints(minWidth: 18),
                        child: Text(
                          '$badge',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.micro(color: Colors.white)
                              .copyWith(
                                  fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: AppTextStyles.micro(color: color)
                    .copyWith(fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
