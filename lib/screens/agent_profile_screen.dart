import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/chat_service.dart';
import '../models/agent_profile.dart';
import '../models/property.dart';
import '../state/app_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/home_nav_bar.dart';
import '../widgets/listing_card.dart';
import '../widgets/property_image.dart';
import '../widgets/state_views.dart';
import 'chat/chat_launcher.dart';
import 'chat/chat_widgets.dart';
import 'property_detail_screen.dart';

/// Agent / owner profile — photo, licence, closed deals, response time,
/// their live listings, and a big Chat button. Signed-in users only (see
/// `openAgentProfile`).
class AgentProfileScreen extends StatefulWidget {
  /// What the listing already knows — shown at once while the rest loads.
  final Agent agent;

  const AgentProfileScreen({super.key, required this.agent});

  @override
  State<AgentProfileScreen> createState() => _AgentProfileScreenState();
}

class _AgentProfileScreenState extends State<AgentProfileScreen> {
  AgentProfile? _profile;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await AppScope.repositoryOf(context).agentProfile(widget.agent.id);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _share() {
    final p = _profile;
    final name = p?.name ?? widget.agent.name;
    final line = p?.roleLine ?? widget.agent.agency;
    Clipboard.setData(ClipboardData(text: '$name — $line, on Home8'));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Profile copied — paste it anywhere to share.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navDark,
      ));
  }

  void _openListing(Property p) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PropertyDetailScreen(propertyId: p.id, preloaded: p),
        ),
      );

  void _seeAll() {
    final p = _profile;
    if (p == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AllListingsScreen(
          title: p.name,
          listings: p.listings,
          onOpen: _openListing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.agent;
    final p = _profile;
    final isMe = p?.chatUid != null && p!.chatUid == ChatService.instance.myUid;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header: back · title · share
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.ink, size: 26),
                  ),
                  Expanded(
                    child: Text(
                      p?.screenTitle ?? 'Agent profile',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.h1().copyWith(fontSize: 21),
                    ),
                  ),
                  IconButton(
                    onPressed: _share,
                    icon: const Icon(Icons.ios_share_rounded,
                        color: AppColors.ink, size: 23),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.only(top: 22, bottom: 32),
                  children: [
                    Center(
                      child: _RingAvatar(
                        url: p?.avatarUrl ?? a.avatarUrl,
                        name: p?.name ?? a.name,
                        verified: p?.verified ?? a.verified,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        p?.name ?? a.name,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.display()
                            .copyWith(fontSize: 29, height: 1.15),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        p?.roleLine ??
                            (a.agency.isEmpty ? 'Agent' : 'Agent · ${a.agency}'),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body(color: AppColors.inkMuted)
                            .copyWith(fontSize: 16.5),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _Chips(profile: p, agent: a),
                    const SizedBox(height: 22),
                    _Stats(profile: p, agent: a),
                    const SizedBox(height: 30),
                    if (_error != null && p == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ErrorStateView(
                          compact: true,
                          message: "Couldn't load this profile.",
                          onRetry: _load,
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 26),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p == null
                                    ? 'Active listings'
                                    : 'Active listings · ${p.activeCount}',
                                style: AppTextStyles.h1()
                                    .copyWith(fontSize: 21),
                              ),
                            ),
                            if ((p?.listings.length ?? 0) > 1)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _seeAll,
                                child: Text('See all',
                                    style: AppTextStyles.bodyStrong(
                                            color: AppColors.primary)
                                        .copyWith(fontSize: 16.5)),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: _ListingTile.height + 24,
                        child: _loading && p == null
                            ? ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.fromLTRB(26, 0, 26, 24),
                                itemCount: 2,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 14),
                                itemBuilder: (_, _) => const SkeletonBox(
                                  width: _ListingTile.width,
                                  height: _ListingTile.height,
                                  radius: 26,
                                ),
                              )
                            : (p?.listings.isEmpty ?? true)
                                ? Padding(
                                    padding: const EdgeInsets.fromLTRB(26, 0, 26, 24),
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(26),
                                        boxShadow: softCardShadow,
                                      ),
                                      child: Text('No active listings right now',
                                          style: AppTextStyles.body(
                                              color: AppColors.inkMuted)),
                                    ),
                                  )
                                : ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    padding:
                                        const EdgeInsets.fromLTRB(26, 0, 26, 24),
                                    itemCount: p!.listings.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 14),
                                    itemBuilder: (_, i) => _ListingTile(
                                      property: p.listings[i],
                                      onTap: () => _openListing(p.listings[i]),
                                    ),
                                  ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!isMe)
              _ChatBar(
                enabled: p == null || p.canChat,
                busy: _loading && p == null,
                onTap: () {
                  final prof = _profile;
                  if (prof != null && !prof.canChat) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(
                        content: Text("This agent isn't on Home8 chat yet. "
                            'Try Call or WhatsApp on their listings.'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.navDark,
                      ));
                    return;
                  }
                  startChat(context, agentId: a.id, profile: prof);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Photo inside a teal ring, with the amber verified tick.
class _RingAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final bool verified;

  const _RingAvatar({required this.url, required this.name, required this.verified});

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0].toUpperCase())
        .join();
    return SizedBox(
      width: 118,
      height: 118,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 118,
            height: 118,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
              border: Border.all(color: AppColors.primary, width: 3.5),
            ),
            child: ChatAvatar(url: url, initials: initials, size: 99),
          ),
          if (verified)
            Positioned(
              right: -2,
              bottom: 4,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 3),
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 19),
              ),
            ),
        ],
      ),
    );
  }
}

/// RERA / licence · role · member since.
class _Chips extends StatelessWidget {
  final AgentProfile? profile;
  final Agent agent;

  const _Chips({required this.profile, required this.agent});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final chips = <(String, Color, Color)>[
      if (p != null && p.licence.isNotEmpty)
        (
          p.isOwner ? 'DEED VERIFIED' : 'RERA #${p.licence.replaceAll(RegExp(r'^(RERA[-\s#]*)', caseSensitive: false), '')}',
          const Color(0xFFE3F1E8),
          AppColors.success,
        ),
      (
        switch (p?.kind) {
          'individual' => 'OWNER',
          'company' => 'COMPANY',
          _ => (p?.verified ?? agent.verified) ? 'VERIFIED AGENT' : 'AGENT',
        },
        AppColors.primaryTint,
        AppColors.primaryDark,
      ),
      if (p != null)
        (
          'SINCE ${p.memberSince}',
          const Color(0xFFFDF1DC),
          AppColors.warning,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (label, bg, fg) in chips)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: AppTextStyles.bodyStrong(color: fg).copyWith(
                    fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.3),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  final AgentProfile? profile;
  final Agent agent;

  const _Stats({required this.profile, required this.agent});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    String response(String r) => r.replaceAll(' min', 'm').replaceAll(' ', '');
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StatCard(
          value: p == null ? '–' : formatThousands(p.closedCount),
          label: 'Closed deals',
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: response(p?.responseTime ?? agent.responseTime),
          label: 'Response',
          valueColor: AppColors.primary,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;

  const _StatCard({
    required this.value,
    required this.label,
    this.valueColor = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: softCardShadow,
      ),
      child: Column(
        children: [
          Text(value,
              style: AppTextStyles.display(color: valueColor)
                  .copyWith(fontSize: 26, height: 1.1)),
          const SizedBox(height: 4),
          Text(label,
              style: AppTextStyles.body(color: AppColors.inkMuted)
                  .copyWith(fontSize: 14.5)),
        ],
      ),
    );
  }
}

class _ListingTile extends StatelessWidget {
  static const double width = 262;
  static const double height = 280;

  final Property property;
  final VoidCallback onTap;

  const _ListingTile({required this.property, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = property;
    final badge = p.badgeLabel;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(26),
          boxShadow: softCardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 160,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PropertyImage(
                    seed: p.gradientSeed,
                    url: p.photos.isEmpty ? null : p.photos.first,
                    decodeWidth: width,
                  ),
                  if (badge.isNotEmpty)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.amber,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(badge,
                            style: AppTextStyles.caption(color: Colors.white)
                                .copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyStrong().copyWith(fontSize: 16.5)),
                  const SizedBox(height: 4),
                  Text(
                    '${p.beds == 0 ? 'Studio' : '${p.beds} Bed'} · '
                    '${formatThousands(p.sqft)} sqft',
                    style: AppTextStyles.caption().copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text('${p.currency} ${p.priceFormatted}',
                      style: AppTextStyles.h2().copyWith(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White panel with the big teal Chat button.
class _ChatBar extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _ChatBar({required this.enabled, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          22, 16, 22, MediaQuery.paddingOf(context).bottom + 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(color: Color(0x0D1B2336), blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.55,
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(999),
              boxShadow: enabled ? tealGlow() : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  NavIcons.chats,
                  width: 21,
                  height: 21,
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
                const SizedBox(width: 12),
                Text('Chat',
                    style: AppTextStyles.h2(color: Colors.white)
                        .copyWith(fontSize: 19, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AllListingsScreen extends StatelessWidget {
  final String title;
  final List<Property> listings;
  final ValueChanged<Property> onOpen;

  const _AllListingsScreen({
    required this.title,
    required this.listings,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
        centerTitle: true,
        title: Text("$title's listings",
            style: AppTextStyles.h2().copyWith(fontSize: 19)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: listings.length,
        itemBuilder: (_, i) => ResultListingCard(
          property: listings[i],
          index: i + 1,
          total: listings.length,
          onTap: () => onOpen(listings[i]),
        ),
      ),
    );
  }
}
