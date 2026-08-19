import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../widgets/home_nav_bar.dart';
import 'coming_soon_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'home_screen.dart';
import 'reels_screen.dart';
import 'search_screen.dart';

/// Hosts the tabbed screens behind the shared floating nav.
///
/// Opens on Reels by default. Reels sits second in the bar, but it is still the
/// first thing a user sees on launch — the feed is the hook, and the bar order
/// follows the design rather than the launch order. The two are deliberately
/// independent: [initialTab] decides what opens, `HomeNavBar` decides what the
/// bar looks like.
///
/// Tabs are built lazily — a screen isn't constructed until first visited, then
/// kept alive. Cold start pays for Reels only.
class MainShell extends StatefulWidget {
  final NavTab initialTab;
  const MainShell({super.key, this.initialTab = NavTab.reels});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late NavTab _tab = widget.initialTab;
  late final Set<NavTab> _visited = {widget.initialTab};

  /// Stack order is fixed and independent of the bar's visual order.
  ///
  /// Profile has no slot in the bar — it's reached from the avatar in the Home
  /// hero — but it lives here as a real tab so switching to it keeps the nav
  /// bar in place and doesn't strand Back.
  static const List<NavTab> _stackOrder = [
    NavTab.discover,
    NavTab.reels,
    NavTab.search,
    NavTab.profile,
  ];

  void switchTab(NavTab tab) {
    switch (tab) {
      case NavTab.chats:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ComingSoonScreen(
              title: 'Chats are under progress',
              message:
                  'Messaging agents from inside the app is still being built. '
                  'For now, use the Email, Call or WhatsApp buttons on any '
                  'listing to reach the agent directly.',
            ),
          ),
        );
      case NavTab.discover:
      case NavTab.reels:
      case NavTab.search:
      case NavTab.profile:
        if (_tab == tab) return;
        setState(() {
          _tab = tab;
          _visited.add(tab);
        });
    }
  }

  /// The raised centre `+`. An action rather than a destination: it opens over
  /// the current tab and leaves the selected tab untouched, so dismissing it
  /// returns the user exactly where they were.
  void _openPostListing() => openPostListingFlow(context);

  Widget _buildTab(NavTab tab) {
    if (!_visited.contains(tab)) return const SizedBox.shrink();
    return switch (tab) {
      NavTab.reels => ReelsScreen(onNavTap: switchTab),
      NavTab.search => SearchScreen(onNavTap: switchTab),
      NavTab.profile => _ProfileTab(onNavTap: switchTab),
      _ => HomeScreen(onNavTap: switchTab),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _stackOrder.indexOf(_tab),
        children: [
          for (final tab in _stackOrder) _buildTab(tab),
        ],
      ),
      bottomNavigationBar: HomeNavBar(
        current: _tab,
        onTap: switchTab,
        onPost: _openPostListing,
      ),
    );
  }
}

/// Hosts the account tab, swapping between the auth screen and the profile
/// screen as the session changes.
///
/// Listening here rather than inside either screen means signing in or out
/// switches the tab contents in place — no navigation, no flash of the wrong
/// screen, and the nav bar never rebuilds.
class _ProfileTab extends StatelessWidget {
  final ValueChanged<NavTab> onNavTap;
  const _ProfileTab({required this.onNavTap});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.authOf(context);
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => auth.isSignedIn
          ? ProfileScreen(onNavTap: onNavTap)
          : const LoginScreen(),
    );
  }
}
