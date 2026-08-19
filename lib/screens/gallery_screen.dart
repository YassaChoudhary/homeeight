import 'package:flutter/material.dart';

import '../models/property.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/property_image.dart';
import 'share_sheet.dart';

/// What kind of media a tile holds. Drives the tile chrome (play button, dashed
/// 360 placeholder) and the filter chips.
enum MediaKind { photo, video, tour360, floorPlan }

/// One item in the gallery. Built from [Property.photos] today; when the
/// backend serves a typed media array (`{url, kind, room}`) this is the shape it
/// maps onto, so only [GalleryScreen.itemsFor] changes.
@immutable
class GalleryItem {
  final String id;
  final String? url;
  final int gradientSeed;
  final MediaKind kind;

  /// Room grouping — "Living", "Bedrooms". Empty when unclassified.
  final String room;

  const GalleryItem({
    required this.id,
    required this.gradientSeed,
    this.url,
    this.kind = MediaKind.photo,
    this.room = '',
  });
}

/// Screen 21 — full-screen dark photo gallery.
///
/// Two behaviours worth knowing:
///
/// 1. **The mosaic is deterministic, not random.** [_Tile] positions follow a
///    fixed repeating pattern — one full-width hero, then pairs — so the same
///    listing always lays out the same way and scroll position stays stable
///    across rebuilds and filter changes.
///
/// 2. **Filters are client-side over an already-loaded list.** The gallery gets
///    its items from the property it was pushed with, so switching chips is a
///    pure filter with no refetch and no loading state. If media moves to its
///    own endpoint later, this becomes an `AsyncController` and the chips gain
///    a loading branch — the tile widgets don't change.
class GalleryScreen extends StatefulWidget {
  final Property property;
  final int initialIndex;

  const GalleryScreen({
    super.key,
    required this.property,
    this.initialIndex = 0,
  });

  /// Derives the media list from a property.
  ///
  /// No photography shipped with the handoff, so when [Property.photos] is
  /// empty this synthesises a deterministic set of gradient tiles seeded off the
  /// listing id — enough to exercise the real layout, including the video and
  /// 360 tiles the Figma shows. Once photos arrive this returns them and the
  /// synthetic branch stops being reached.
  static List<GalleryItem> itemsFor(Property p) {
    const rooms = ['Living', 'Living', 'Bedrooms', 'Bedrooms', 'Exterior'];

    if (p.photos.isNotEmpty) {
      return [
        for (var i = 0; i < p.photos.length; i++)
          GalleryItem(
            id: '${p.id}_$i',
            url: p.photos[i],
            gradientSeed: p.gradientSeed + i,
            room: rooms[i % rooms.length],
          ),
      ];
    }

    return [
      for (var i = 0; i < 5; i++)
        GalleryItem(
          id: '${p.id}_$i',
          gradientSeed: p.gradientSeed + i,
          room: rooms[i % rooms.length],
        ),
      GalleryItem(
        id: '${p.id}_video',
        gradientSeed: p.gradientSeed + 7,
        kind: MediaKind.video,
        room: 'Living',
      ),
      GalleryItem(
        id: '${p.id}_360',
        gradientSeed: p.gradientSeed + 9,
        kind: MediaKind.tour360,
      ),
    ];
  }

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  static const Color _bg = Color(0xFF0E1626);

  late final List<GalleryItem> _all = GalleryScreen.itemsFor(widget.property);

  /// null = "All".
  String? _filter;

  @override
  void initState() {
    super.initState();
    // Tapping a specific photo on the detail hero should land on that photo,
    // not just the grid. The grid stays underneath, so Back returns to it.
    if (widget.initialIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openViewerAt(widget.initialIndex);
      });
    }
  }

  List<String> get _chips {
    final rooms = <String>{for (final i in _all) if (i.room.isNotEmpty) i.room};
    return [
      'All',
      ...rooms,
      if (_all.any((i) => i.kind == MediaKind.tour360)) '360°',
      if (_all.any((i) => i.kind == MediaKind.floorPlan)) 'Plan',
    ];
  }

  List<GalleryItem> get _visible {
    final f = _filter;
    if (f == null) return _all;
    if (f == '360°') {
      return _all.where((i) => i.kind == MediaKind.tour360).toList();
    }
    if (f == 'Plan') {
      return _all.where((i) => i.kind == MediaKind.floorPlan).toList();
    }
    return _all.where((i) => i.room == f).toList();
  }

  void _openViewer(int indexInVisible) {
    final tapped = _visible[indexInVisible];
    if (tapped.kind == MediaKind.tour360) return;
    _openViewerFor(tapped, _visible);
  }

  /// Used by [initState] when the caller asked for a specific photo, where the
  /// index refers to the unfiltered list.
  void _openViewerAt(int indexInAll) {
    if (indexInAll >= _all.length) return;
    _openViewerFor(_all[indexInAll], _all);
  }

  void _openViewerFor(GalleryItem target, List<GalleryItem> source) {
    // The 360 tile isn't a photo, so it never appears in the pager.
    final items = source.where((i) => i.kind != MediaKind.tour360).toList();
    if (items.isEmpty) return;
    final start = items.indexWhere((i) => i.id == target.id);
    if (start < 0) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoViewer(items: items, initialIndex: start),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _GalleryHeader(
              count: _all.length,
              onClose: () => Navigator.of(context).maybePop(),
              onShare: () => ShareSheet.show(context, widget.property),
            ),
            _FilterChips(
              chips: _chips,
              active: _filter ?? 'All',
              onSelect: (c) => setState(() => _filter = c == 'All' ? null : c),
            ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        'Nothing here yet.',
                        style: AppTextStyles.body(color: Colors.white54),
                      ),
                    )
                  : _Mosaic(
                      items: visible,
                      onTap: _openViewer,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryHeader extends StatelessWidget {
  final int count;
  final VoidCallback onClose;
  final VoidCallback onShare;

  const _GalleryHeader({
    required this.count,
    required this.onClose,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          _RoundBtn(icon: Icons.close_rounded, onTap: onClose),
          Expanded(
            child: Text(
              'Photos · $count',
              textAlign: TextAlign.center,
              style: AppTextStyles.h1(color: Colors.white).copyWith(fontSize: 20),
            ),
          ),
          _RoundBtn(icon: Icons.ios_share_rounded, onTap: onShare),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final List<String> chips;
  final String active;
  final ValueChanged<String> onSelect;

  const _FilterChips({
    required this.chips,
    required this.active,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 9),
        itemBuilder: (context, i) {
          final chip = chips[i];
          final isActive = chip == active;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(chip),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? Colors.white : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                chip,
                style: AppTextStyles.bodyStrong(
                  color: isActive ? AppColors.ink : Colors.white70,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Fixed mosaic: index 0 spans the full width, everything after it pairs up.
class _Mosaic extends StatelessWidget {
  final List<GalleryItem> items;
  final ValueChanged<int> onTap;

  const _Mosaic({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    for (var i = 0; i < items.length;) {
      if (i == 0) {
        rows.add(
          _Tile(
            item: items[0],
            aspectRatio: 1.32,
            showCoverBadge: true,
            onTap: () => onTap(0),
          ),
        );
        i = 1;
        continue;
      }

      final left = items[i];
      final right = i + 1 < items.length ? items[i + 1] : null;

      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Tile(
                item: left,
                aspectRatio: 1.13,
                onTap: () => onTap(i),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: right == null
                  ? const SizedBox.shrink()
                  : _Tile(
                      item: right,
                      aspectRatio: 1.13,
                      onTap: () => onTap(i + 1),
                    ),
            ),
          ],
        ),
      );
      i += 2;
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      itemCount: rows.length,
      cacheExtent: 900,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => rows[i],
    );
  }
}

class _Tile extends StatelessWidget {
  final GalleryItem item;
  final double aspectRatio;
  final bool showCoverBadge;
  final VoidCallback onTap;

  const _Tile({
    required this.item,
    required this.aspectRatio,
    required this.onTap,
    this.showCoverBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    // The 360 tile is a dashed outline placeholder, not media.
    if (item.kind == MediaKind.tour360) {
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: CustomPaint(
          painter: _DashedBorderPainter(),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 1.6),
                  ),
                  child: const Icon(Icons.threesixty_rounded,
                      color: Colors.white70, size: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  '360° TOUR',
                  style: AppTextStyles.micro(color: Colors.white70)
                      .copyWith(fontSize: 12, letterSpacing: 0.6),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: PropertyImage(
          seed: item.gradientSeed,
          url: item.url,
          decodeWidth: showCoverBadge ? width : width / 2,
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              if (showCoverBadge)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'COVER',
                      style: AppTextStyles.micro(color: Colors.white)
                          .copyWith(fontSize: 11, letterSpacing: 0.5),
                    ),
                  ),
                ),
              if (item.kind == MediaKind.video)
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: AppColors.ink, size: 30),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );

    // Walk the rounded-rect path and stroke alternate segments.
    final path = Path()..addRRect(rrect);
    const dash = 7.0;
    const gap = 6.0;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Fullscreen viewer
// ---------------------------------------------------------------------------

/// Swipeable fullscreen pager, opened by tapping a tile.
class _PhotoViewer extends StatefulWidget {
  final List<GalleryItem> items;
  final int initialIndex;

  const _PhotoViewer({required this.items, required this.initialIndex});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late final ValueNotifier<int> _index =
      ValueNotifier<int>(widget.initialIndex);

  @override
  void dispose() {
    _controller.dispose();
    _index.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Page index lives in a ValueNotifier so swiping repaints the
          // counter, not the PageView.
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => _index.value = i,
            itemBuilder: (context, i) => Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: PropertyImage(
                  seed: widget.items[i].gradientSeed,
                  url: widget.items[i].url,
                  fit: BoxFit.contain,
                  decodeWidth: MediaQuery.sizeOf(context).width,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _RoundBtn(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<int>(
                    valueListenable: _index,
                    builder: (context, i, _) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${i + 1} / ${widget.items.length}',
                        style: AppTextStyles.caption(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
