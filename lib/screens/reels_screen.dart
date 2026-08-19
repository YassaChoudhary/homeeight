import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/async_value.dart';
import '../models/property.dart';
import '../state/app_scope.dart';
import '../state/listings_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/home_nav_bar.dart';
import '../widgets/pill_button.dart';
import '../widgets/property_image.dart';
import 'property_detail_screen.dart';

/// Full-bleed vertical feed.
///
/// Layout corrections against the Figma frame:
///  * the agency header is pinned to the TOP and centred. Previously the Row
///    sat inside an unconstrained SafeArea > Padding, so it filled the height
///    and centred itself vertically — which is why the name floated mid-screen.
///  * the action rail sits on the right at roughly mid-height, not just above
///    the nav bar.
///  * "Property details" is right-aligned above the nav bar, not centred.
///  * the save glyph uses NavIcons.reelSave (the bookmark ribbon), which the
///    export had filed under the reels tab's name.
class ReelsScreen extends StatefulWidget {
  final ValueChanged<NavTab> onNavTap;
  const ReelsScreen({super.key, required this.onNavTap});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen>
    with AutomaticKeepAliveClientMixin {
  final PageController _controller = PageController();
  late final AsyncController<List<Reel>> _reels;

  /// Page index lives in a notifier rather than State so swiping repaints only
  /// the overlay, never the PageView itself.
  final ValueNotifier<int> _index = ValueNotifier<int>(0);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reels = AsyncController<List<Reel>>(
      () => AppScope.repositoryOf(context).reels(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _reels.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _index.dispose();
    _reels.dispose();
    super.dispose();
  }

  void _openDetail(String propertyId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(propertyId: propertyId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: _reels,
      builder: (context, _) {
        return _reels.state.when(
          loading: () => const ColoredBox(
            color: AppColors.navDark,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
              ),
            ),
          ),
          error: (_) => ColoredBox(
            color: AppColors.navDark,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Reels aren't available right now.",
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    OverlayPillButton(
                      label: 'Try again',
                      icon: Icons.refresh_rounded,
                      onTap: _reels.load,
                    ),
                  ],
                ),
              ),
            ),
          ),
          data: (reels) => _ReelsFeed(
            reels: reels,
            controller: _controller,
            index: _index,
            onOpenDetail: _openDetail,
          ),
        );
      },
    );
  }
}

class _ReelsFeed extends StatelessWidget {
  final List<Reel> reels;
  final PageController controller;
  final ValueNotifier<int> index;
  final ValueChanged<String> onOpenDetail;

  const _ReelsFeed({
    required this.reels,
    required this.controller,
    required this.index,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    if (reels.isEmpty) {
      return const ColoredBox(color: AppColors.navDark);
    }

    final navSpace = HomeNavBar.reservedSpace(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: controller,
          scrollDirection: Axis.vertical,
          itemCount: reels.length,
          onPageChanged: (i) => index.value = i,
          itemBuilder: (context, i) {
            final reel = reels[i];
            return PropertyImage(
              seed: reel.gradientSeed,
              url: reel.mediaUrl,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.2, 0.62, 1],
                    colors: [
                      Color(0x73000000),
                      Color(0x00000000),
                      Color(0x40000000),
                      Color(0xBF000000),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        // Agency header — top, centred.
        Positioned(
          top: topInset + 14,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (context, i, _) => _AgencyHeader(agency: reels[i].agency),
          ),
        ),

        // Action rail — right side, roughly mid-height as in the design.
        Positioned(
          right: 18,
          top: screenHeight * 0.42,
          child: ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (context, i, _) => _ActionRail(reel: reels[i]),
          ),
        ),

        // Property details — right-aligned, just above the nav bar.
        Positioned(
          right: 16,
          bottom: navSpace + 16,
          child: ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (context, i, _) => OverlayPillButton(
              label: 'Property details',
              icon: Icons.info_outline_rounded,
              onTap: () => onOpenDetail(reels[i].propertyId),
            ),
          ),
        ),
      ],
    );
  }
}

class _AgencyHeader extends StatelessWidget {
  final Agent agency;
  const _AgencyHeader({required this.agency});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.max,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: Color(0xFF241E3D),
            shape: BoxShape.circle,
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: agency.avatarUrl == null
              ? const Icon(Icons.language_rounded,
                  color: Color(0xFFB79CFF), size: 20)
              : Image.network(
                  agency.avatarUrl!,
                  fit: BoxFit.cover,
                  width: 38,
                  height: 38,
                  errorBuilder: (_, _, _) => const Icon(
                      Icons.language_rounded,
                      color: Color(0xFFB79CFF),
                      size: 20),
                ),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.5,
          ),
          child: Text(
            agency.agency.isEmpty ? agency.name : agency.agency,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyStrong(color: Colors.white)
                .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        if (agency.verified) ...[
          const SizedBox(width: 6),
          const Icon(Icons.verified_rounded, color: Colors.white, size: 17),
        ],
      ],
    );
  }
}

class _ActionRail extends StatefulWidget {
  final Reel reel;
  const _ActionRail({required this.reel});

  @override
  State<_ActionRail> createState() => _ActionRailState();
}

class _ActionRailState extends State<_ActionRail> {
  bool _liked = false;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.savedOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailAction(
          asset: NavIcons.heart,
          label: formatCount(widget.reel.likes + (_liked ? 1 : 0)),
          tint: _liked ? AppColors.accent : Colors.white,
          onTap: () => setState(() => _liked = !_liked),
        ),
        const SizedBox(height: 26),
        _RailAction(
          asset: NavIcons.comment,
          label: formatCount(widget.reel.comments),
          onTap: () {},
        ),
        const SizedBox(height: 26),
        ValueListenableBuilder<Set<String>>(
          valueListenable: store,
          builder: (context, saved, _) {
            final isSaved = saved.contains(widget.reel.propertyId);
            return _RailAction(
              asset: NavIcons.reelSave,
              label: null,
              tint: isSaved ? AppColors.accent : Colors.white,
              onTap: () => store.toggle(widget.reel.propertyId),
            );
          },
        ),
      ],
    );
  }
}

class _RailAction extends StatelessWidget {
  final String asset;
  final String? label;
  final Color tint;
  final VoidCallback onTap;

  const _RailAction({
    required this.asset,
    required this.label,
    required this.onTap,
    this.tint = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: SvgPicture.asset(
              asset,
              colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 6),
            Text(
              label!,
              style: AppTextStyles.bodyStrong(color: Colors.white)
                  .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}
