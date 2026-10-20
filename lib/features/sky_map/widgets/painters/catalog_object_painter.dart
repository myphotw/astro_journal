import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/catalog_type.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/sky_map_render_object.dart';
import '../sky_map_object_symbol.dart';

/// Layer 4: Catalog 천체 — 각크기 범위(원/타원) + 종류별 심볼.
class CatalogObjectPainter extends CustomPainter {
  CatalogObjectPainter({
    required this.objects,
    required this.selectedId,
    required this.showLabels,
    this.occupiedLabels,
  });

  final List<SkyMapRenderObject> objects;
  final String? selectedId;
  final bool showLabels;
  final List<Rect>? occupiedLabels;

  @visibleForTesting
  static Color labelColorFor(SkyMapRenderObject object, bool selected) {
    if (object.catalog == CatalogType.messier) {
      return AppColors.skyMapMessierLabel;
    }
    return selected
        ? object.catalog.accentColor
        : AppColors.textPrimary.withValues(alpha: 0.9);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final obj in objects) {
      final selected = obj.catalogId == selectedId;
      final color = obj.catalog.accentColor;
      final center = Offset(obj.screenX, obj.screenY);

      if (selected) {
        canvas.drawCircle(
          center,
          math.max(obj.renderWidth, obj.renderHeight) / 2 + 10,
          Paint()..color = color.withValues(alpha: 0.15),
        );
      }

      // 1) 천체 범위(각크기) — 기존처럼 유지
      _drawExtent(canvas, obj, color, selected);

      // 2) 종류별 심볼 (중심에 고정 크기)
      final symbolSize = math
          .min(12.0, math.max(obj.renderWidth, obj.renderHeight) * 0.45)
          .clamp(7.0, 12.0);
      SkyMapObjectSymbolPainter.paint(
        canvas,
        center: center,
        kind: SkyMapObjectSymbolPainter.kindFor(obj.shapeKind),
        color: color,
        size: symbolSize,
        selected: selected,
      );

      final shouldLabel =
          selected ||
          (showLabels &&
              (obj.catalog == CatalogType.messier ||
                  obj.renderWidth >= 28 ||
                  (obj.magnitude != null && obj.magnitude! <= 8)));
      if (shouldLabel) {
        final style = TextStyle(
          color: labelColorFor(obj, selected),
          fontSize: selected ? 12 : 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
        final painter = TextPainter(
          text: TextSpan(text: obj.displayName, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final distance = math.max(obj.renderHeight / 2, 6) + 4;
        final candidates = <Offset>[
          Offset(
            center.dx - painter.width / 2,
            center.dy - distance - painter.height,
          ),
          Offset(center.dx + distance, center.dy - painter.height / 2),
          Offset(center.dx - painter.width / 2, center.dy + distance),
          Offset(
            center.dx - distance - painter.width,
            center.dy - painter.height / 2,
          ),
        ];
        Offset? labelOffset;
        Rect? labelBounds;
        for (final candidate in candidates) {
          final bounds = (candidate & painter.size).inflate(2);
          if (_canPlaceLabel(bounds, size, force: selected)) {
            labelOffset = candidate;
            labelBounds = bounds;
            break;
          }
        }
        if (labelOffset != null && labelBounds != null) {
          if (selected) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                labelBounds.inflate(2),
                const Radius.circular(4),
              ),
              Paint()..color = const Color(0xB3050912),
            );
          }
          painter.paint(canvas, labelOffset);
          occupiedLabels?.add(labelBounds);
        }
      }
    }
  }

  bool _canPlaceLabel(Rect bounds, Size size, {required bool force}) {
    if (!(Offset.zero & size).overlaps(bounds)) return false;
    if (force) return true;
    final occupied = occupiedLabels;
    if (occupied == null) return true;
    return !occupied.any((rect) => rect.overlaps(bounds));
  }

  void _drawExtent(
    Canvas canvas,
    SkyMapRenderObject obj,
    Color color,
    bool selected,
  ) {
    final center = Offset(obj.screenX, obj.screenY);
    final stroke = Paint()
      ..color = color.withValues(alpha: selected ? 0.85 : 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.6 : 1.25;
    final fill = Paint()
      ..color = color.withValues(alpha: selected ? 0.18 : 0.10);

    if (obj.shapeKind == SkyMapShapeKind.galaxy) {
      final rect = Rect.fromCenter(
        center: center,
        width: obj.renderWidth,
        height: obj.renderHeight,
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      final pa = (obj.positionAngleDeg ?? 0) * math.pi / 180;
      canvas.rotate(pa);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawOval(rect, fill);
      canvas.drawOval(rect, stroke);
      canvas.restore();
      return;
    }

    final radius = math.max(obj.renderWidth, obj.renderHeight) / 2;
    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius, stroke);
  }

  @override
  bool shouldRepaint(covariant CatalogObjectPainter oldDelegate) {
    return oldDelegate.objects != objects ||
        oldDelegate.selectedId != selectedId ||
        oldDelegate.showLabels != showLabels;
  }
}
