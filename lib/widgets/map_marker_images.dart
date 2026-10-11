import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Draws the map markers as PNG images, the format map annotations take.
///
/// Drawn at the screen's pixel ratio, so they're crisp on every phone — the
/// map scales them back to logical size. Cached by content: the same price at
/// the same state is drawn once.
class MapMarkerImages {
  MapMarkerImages._();

  static final Map<String, Future<Uint8List>> _cache = {};

  /// Price pill — "AED 96K". White with dark text normally; teal with white
  /// text when [selected]. A small pointer at the bottom marks the spot.
  static Future<Uint8List> pricePill(
    String label, {
    required bool selected,
    required double pixelRatio,
  }) {
    final key = 'pill|$label|$selected|$pixelRatio';
    return _cache[key] ??= _drawPill(label, selected, pixelRatio);
  }

  /// Round teal pin with a white ring — a single property's spot.
  static Future<Uint8List> dot({required double pixelRatio}) {
    final key = 'dot|$pixelRatio';
    return _cache[key] ??= _drawDot(pixelRatio);
  }

  static Future<Uint8List> _drawPill(
      String label, bool selected, double ratio) async {
    final fill = selected ? AppColors.primary : Colors.white;
    final ink = selected ? Colors.white : AppColors.ink;

    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 13 * ratio,
          fontWeight: FontWeight.w700,
          color: ink,
          fontFamily: 'CircularStd',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final padX = 11 * ratio;
    final padY = 6.5 * ratio;
    final pointer = 6 * ratio;
    final shadow = 4 * ratio;
    final w = text.width + padX * 2;
    final h = text.height + padY * 2;
    final canvasW = w + shadow * 2;
    final canvasH = h + pointer + shadow * 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(shadow, shadow, w, h),
      Radius.circular(h / 2),
    );
    final path = Path()
      ..addRRect(body)
      ..moveTo(shadow + w / 2 - pointer, shadow + h - 1)
      ..lineTo(shadow + w / 2, shadow + h + pointer)
      ..lineTo(shadow + w / 2 + pointer, shadow + h - 1)
      ..close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.5), 2 * ratio, true);
    canvas.drawPath(path, Paint()..color = fill);
    if (!selected) {
      canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 * ratio
          ..color = AppColors.line,
      );
    }
    text.paint(canvas, Offset(shadow + padX, shadow + padY));

    return _toPng(recorder, canvasW, canvasH);
  }

  static Future<Uint8List> _drawDot(double ratio) async {
    final size = 30 * ratio;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final c = Offset(size / 2, size / 2);
    canvas.drawCircle(
      c.translate(0, 1.5 * ratio),
      11 * ratio,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * ratio),
    );
    canvas.drawCircle(c, 11 * ratio, Paint()..color = Colors.white);
    canvas.drawCircle(c, 7.5 * ratio, Paint()..color = AppColors.primary);
    return _toPng(recorder, size, size);
  }

  static Future<Uint8List> _toPng(
      ui.PictureRecorder recorder, double w, double h) async {
    final image =
        await recorder.endRecording().toImage(w.ceil(), h.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}

/// "AED 96K", "AED 1.2M" — short enough for a map pill.
String compactPrice(String currency, int price) {
  String n;
  if (price >= 1000000) {
    final m = price / 1000000;
    n = '${m >= 10 ? m.round() : _trim(m.toStringAsFixed(1))}M';
  } else if (price >= 1000) {
    n = '${(price / 1000).round()}K';
  } else {
    n = '$price';
  }
  return '$currency $n';
}

String _trim(String s) => s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
