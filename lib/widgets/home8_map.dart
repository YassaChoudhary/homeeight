import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;

import '../core/env.dart';
import '../models/geo.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'map_marker_images.dart';

/// One marker on a [Home8Map].
@immutable
class MapPin {
  final String id;
  final GeoPoint point;

  /// Text on the pin ("AED 96K"). Null draws a plain round pin.
  final String? label;

  const MapPin({required this.id, required this.point, this.label});

  @override
  bool operator ==(Object other) =>
      other is MapPin &&
      other.id == id &&
      other.point == point &&
      other.label == label;

  @override
  int get hashCode => Object.hash(id, point, label);
}

/// What's on screen after the map stops moving.
@immutable
class MapViewport {
  final GeoPoint center;
  final GeoBounds bounds;
  final double zoom;

  /// True when the user dragged or zoomed since the last report — as opposed
  /// to the app moving the camera. Drives the "Search this area" button.
  final bool movedByUser;

  const MapViewport({
    required this.center,
    required this.bounds,
    required this.zoom,
    required this.movedByUser,
  });
}

/// Lets a screen move the camera ("Use my location", "focus this listing").
class Home8MapController {
  mbx.MapboxMap? _map;

  bool get isReady => _map != null;

  Future<void> flyTo(GeoPoint point, {double? zoom, int durationMs = 900}) async {
    final map = _map;
    if (map == null) return;
    await map.flyTo(
      mbx.CameraOptions(center: _toPoint(point), zoom: zoom),
      mbx.MapAnimationOptions(duration: durationMs),
    );
  }

  Future<GeoPoint?> center() async {
    final map = _map;
    if (map == null) return null;
    final state = await map.getCameraState();
    return _fromPoint(state.center);
  }
}

/// The app's map. **The only file that imports the map SDK** (Mapbox) — every
/// screen talks in [GeoPoint], [MapPin] and [GeoBounds], so changing provider
/// later (e.g. Google Maps) means rewriting this file, not the screens.
///
/// Built for growth: nearby schools/hospitals become another pin set, and
/// "draw an area" becomes a polygon layer here plus a polygon filter in SQL.
///
/// Without `MAPBOX_ACCESS_TOKEN` it renders [MapUnavailable] instead of
/// crashing, so the app still runs on a fresh clone.
class Home8Map extends StatefulWidget {
  final GeoPoint initialCenter;
  final double initialZoom;

  final List<MapPin> pins;
  final String? selectedPinId;
  final ValueChanged<String>? onPinTap;

  /// Shades an approximate area (e.g. around a listing whose exact spot is
  /// private): a circle of [areaRadiusM] metres around [area].
  final GeoPoint? area;
  final double areaRadiusM;

  /// False makes the map a static picture: no pan, zoom or rotate. Used for
  /// small previews inside scrolling screens.
  final bool interactive;

  /// Inside a scrolling page, the map should win pan gestures over the page.
  final bool claimGestures;

  final ValueChanged<MapViewport>? onViewportIdle;
  final VoidCallback? onTap;
  final Home8MapController? controller;

  /// Show the blue "you are here" dot (needs location permission).
  final bool showMyLocation;

  const Home8Map({
    super.key,
    required this.initialCenter,
    this.initialZoom = 13,
    this.pins = const [],
    this.selectedPinId,
    this.onPinTap,
    this.area,
    this.areaRadiusM = 400,
    this.interactive = true,
    this.claimGestures = false,
    this.onViewportIdle,
    this.onTap,
    this.controller,
    this.showMyLocation = false,
  });

  @override
  State<Home8Map> createState() => _Home8MapState();
}

class _Home8MapState extends State<Home8Map> {
  mbx.MapboxMap? _map;
  mbx.PointAnnotationManager? _pinLayer;
  mbx.PolygonAnnotationManager? _areaLayer;
  mbx.Cancelable? _tapSub;

  /// Mapbox annotation id → our pin id, for tap handling.
  final Map<String, String> _annotationToPin = {};

  bool _userMoved = false;
  int _syncGeneration = 0;

  @override
  void didUpdateWidget(Home8Map old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.pins, widget.pins) ||
        old.selectedPinId != widget.selectedPinId) {
      _syncPins();
    }
    if (old.area != widget.area || old.areaRadiusM != widget.areaRadiusM) {
      _syncArea();
    }
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    widget.controller?._map = null;
    super.dispose();
  }

  Future<void> _onMapCreated(mbx.MapboxMap map) async {
    _map = map;
    widget.controller?._map = map;

    // Keep Mapbox's logo and ⓘ attribution (their terms require it); drop
    // the scale bar, and the compass on static previews.
    await map.scaleBar.updateSettings(mbx.ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(
        mbx.CompassSettings(enabled: widget.interactive));

    if (!widget.interactive) {
      await map.gestures.updateSettings(mbx.GesturesSettings(
        scrollEnabled: false,
        rotateEnabled: false,
        pitchEnabled: false,
        pinchToZoomEnabled: false,
        doubleTapToZoomInEnabled: false,
        doubleTouchToZoomOutEnabled: false,
        quickZoomEnabled: false,
        simultaneousRotateAndPinchToZoomEnabled: false,
      ));
    } else {
      // Real-estate maps read better flat and north-up.
      await map.gestures.updateSettings(
          mbx.GesturesSettings(rotateEnabled: false, pitchEnabled: false));
    }

    if (widget.showMyLocation) {
      await map.location.updateSettings(mbx.LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        pulsingColor: AppColors.primary.toARGB32(),
      ));
    }

    // Area shade first, so pins draw above it.
    _areaLayer = await map.annotations.createPolygonAnnotationManager();
    _pinLayer = await map.annotations.createPointAnnotationManager();
    _tapSub = _pinLayer!.tapEvents(onTap: (annotation) {
      final pinId = _annotationToPin[annotation.id];
      if (pinId != null) widget.onPinTap?.call(pinId);
    });

    await _syncArea();
    await _syncPins();
  }

  Future<void> _syncPins() async {
    final layer = _pinLayer;
    if (layer == null || !mounted) return;
    final generation = ++_syncGeneration;
    final ratio = MediaQuery.devicePixelRatioOf(context);

    // Draw all images first, then swap the layer contents in one go.
    final images = <Uint8List>[];
    for (final pin in widget.pins) {
      final label = pin.label;
      images.add(label == null
          ? await MapMarkerImages.dot(pixelRatio: ratio)
          : await MapMarkerImages.pricePill(label,
              selected: pin.id == widget.selectedPinId, pixelRatio: ratio));
    }
    // A newer sync started while drawing — let that one win.
    if (generation != _syncGeneration || !mounted) return;

    await layer.deleteAll();
    _annotationToPin.clear();
    if (widget.pins.isEmpty) return;

    final options = <mbx.PointAnnotationOptions>[
      for (var i = 0; i < widget.pins.length; i++)
        mbx.PointAnnotationOptions(
          geometry: _toPoint(widget.pins[i].point),
          image: images[i],
          // Pills point down at the spot; plain pins sit centred on it.
          iconAnchor: widget.pins[i].label == null
              ? mbx.IconAnchor.CENTER
              : mbx.IconAnchor.BOTTOM,
          // The selected pill draws above its neighbours.
          symbolSortKey: widget.pins[i].id == widget.selectedPinId ? 10 : 0,
        ),
    ];
    final created = await layer.createMulti(options);
    for (var i = 0; i < created.length; i++) {
      final annotation = created[i];
      if (annotation != null) _annotationToPin[annotation.id] = widget.pins[i].id;
    }
  }

  Future<void> _syncArea() async {
    final layer = _areaLayer;
    if (layer == null) return;
    await layer.deleteAll();
    final area = widget.area;
    if (area == null) return;
    final ring = circleRing(area, widget.areaRadiusM);
    await layer.create(mbx.PolygonAnnotationOptions(
      geometry: mbx.Polygon(coordinates: [
        [for (final p in ring) mbx.Position(p.lng, p.lat)],
      ]),
      fillColor: AppColors.primary.toARGB32(),
      fillOpacity: 0.22,
      fillOutlineColor: AppColors.primary.toARGB32(),
    ));
  }

  Future<void> _onIdle(mbx.MapIdleEventData _) async {
    final map = _map;
    final callback = widget.onViewportIdle;
    if (map == null || callback == null) return;
    final state = await map.getCameraState();
    final bounds = await map.coordinateBoundsForCamera(mbx.CameraOptions(
      center: state.center,
      zoom: state.zoom,
      bearing: state.bearing,
      pitch: state.pitch,
      padding: state.padding,
    ));
    if (!mounted) return;
    final moved = _userMoved;
    _userMoved = false;
    callback(MapViewport(
      center: _fromPoint(state.center),
      bounds: GeoBounds(_fromPoint(bounds.southwest), _fromPoint(bounds.northeast)),
      zoom: state.zoom,
      movedByUser: moved,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!Env.hasMapbox) return const MapUnavailable();

    final map = mbx.MapWidget(
      key: const ValueKey('home8-map'),
      styleUri: mbx.MapboxStyles.MAPBOX_STREETS,
      cameraOptions: mbx.CameraOptions(
        center: _toPoint(widget.initialCenter),
        zoom: widget.initialZoom,
      ),
      onMapCreated: _onMapCreated,
      onMapIdleListener: _onIdle,
      onScrollListener: (_) => _userMoved = true,
      onZoomListener: (_) => _userMoved = true,
      // ignore: deprecated_member_use
      onTapListener: widget.onTap == null ? null : (_) => widget.onTap!(),
      gestureRecognizers: widget.claimGestures && widget.interactive
          ? <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer()),
            }
          : null,
    );

    // A static preview still needs taps to open the full map; the map itself
    // has gestures off, so a transparent layer on top takes the tap.
    if (!widget.interactive && widget.onTap != null) {
      return Stack(
        children: [
          map,
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
            ),
          ),
        ],
      );
    }
    return map;
  }
}

mbx.Point _toPoint(GeoPoint p) => mbx.Point(coordinates: mbx.Position(p.lng, p.lat));

GeoPoint _fromPoint(mbx.Point p) =>
    GeoPoint(p.coordinates.lat.toDouble(), p.coordinates.lng.toDouble());

/// Shown where a map would be when no Mapbox token is configured.
class MapUnavailable extends StatelessWidget {
  const MapUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE8EEE9),
      padding: const EdgeInsets.all(AppSpacing.s4),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map_outlined, color: AppColors.inkMuted, size: 30),
          const SizedBox(height: 8),
          Text(
            'Map unavailable',
            style: AppTextStyles.bodyStrong(color: AppColors.inkMuted),
          ),
          const SizedBox(height: 2),
          Text(
            'Add MAPBOX_ACCESS_TOKEN to env.json',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption(),
          ),
        ],
      ),
    );
  }
}

/// Round white button floating over a map (back, my location, recentre).
class MapCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const MapCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, size: 21, color: AppColors.ink),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
