import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/object_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/sky_map_render_object.dart';

/// 성도·별자리 목록용 천체 종류 심볼.
enum SkyMapObjectSymbolKind {
  galaxy,
  openCluster,
  globularCluster,
  nebula,
  planetaryNebula,
  point,
}

/// 범례와 동일한 천체 종류 필터.
enum SkyMapObjectTypeFilter {
  galaxy('은하', SkyMapObjectSymbolKind.galaxy),
  openCluster('산개성단', SkyMapObjectSymbolKind.openCluster),
  globularCluster('구상성단', SkyMapObjectSymbolKind.globularCluster),
  nebula('성운', SkyMapObjectSymbolKind.nebula),
  planetaryNebula('행성상성운', SkyMapObjectSymbolKind.planetaryNebula);

  const SkyMapObjectTypeFilter(this.label, this.symbolKind);

  final String label;
  final SkyMapObjectSymbolKind symbolKind;

  static const legendFilters = SkyMapObjectTypeFilter.values;

  static SkyMapObjectTypeFilter? forObjectType(ObjectType type) {
    final kind = type.skyMapSymbolKind;
    for (final filter in values) {
      if (filter.symbolKind == kind) return filter;
    }
    return null;
  }

  bool matches(ObjectType type) => forObjectType(type) == this;
}

extension SkyMapObjectSymbolKindX on ObjectType {
  SkyMapObjectSymbolKind get skyMapSymbolKind {
    if (this == ObjectType.galaxy || this == ObjectType.galaxyGroup) {
      return SkyMapObjectSymbolKind.galaxy;
    }
    if (this == ObjectType.planetaryNebula) {
      return SkyMapObjectSymbolKind.planetaryNebula;
    }
    if (isNebula ||
        this == ObjectType.starCloud ||
        this == ObjectType.nebulaWithCluster) {
      return SkyMapObjectSymbolKind.nebula;
    }
    if (this == ObjectType.openCluster) {
      return SkyMapObjectSymbolKind.openCluster;
    }
    if (this == ObjectType.globularCluster) {
      return SkyMapObjectSymbolKind.globularCluster;
    }
    return SkyMapObjectSymbolKind.point;
  }
}

/// 고정 크기 천체 종류 심볼 (목록·성도 중심 마커).
class SkyMapObjectSymbol extends StatelessWidget {
  const SkyMapObjectSymbol({
    super.key,
    required this.kind,
    required this.color,
    this.size = 16,
  });

  final SkyMapObjectSymbolKind kind;
  final Color color;
  final double size;

  factory SkyMapObjectSymbol.fromObjectType({
    Key? key,
    required ObjectType objectType,
    required Color color,
    double size = 16,
  }) {
    return SkyMapObjectSymbol(
      key: key,
      kind: objectType.skyMapSymbolKind,
      color: color,
      size: size,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SymbolPainter(kind: kind, color: color),
      ),
    );
  }
}

/// Canvas에 직접 그릴 때 사용.
abstract final class SkyMapObjectSymbolPainter {
  static SkyMapObjectSymbolKind kindFor(SkyMapShapeKind shape) {
    return switch (shape) {
      SkyMapShapeKind.galaxy => SkyMapObjectSymbolKind.galaxy,
      SkyMapShapeKind.openCluster => SkyMapObjectSymbolKind.openCluster,
      SkyMapShapeKind.globularCluster => SkyMapObjectSymbolKind.globularCluster,
      SkyMapShapeKind.nebula => SkyMapObjectSymbolKind.nebula,
      SkyMapShapeKind.planetaryNebula => SkyMapObjectSymbolKind.planetaryNebula,
      SkyMapShapeKind.point => SkyMapObjectSymbolKind.point,
    };
  }

  static void paint(
    Canvas canvas, {
    required Offset center,
    required SkyMapObjectSymbolKind kind,
    required Color color,
    double size = 10,
    bool selected = false,
  }) {
    final stroke = Paint()
      ..color = color.withValues(alpha: selected ? 1.0 : 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.8 : 1.4;
    // 채움 심볼은 색만으로도 구분되도록 불투명도를 높인다.
    final solidFill = Paint()
      ..color = color.withValues(alpha: selected ? 0.92 : 0.78);
    final lightFill = Paint()
      ..color = color.withValues(alpha: selected ? 0.28 : 0.14);

    switch (kind) {
      case SkyMapObjectSymbolKind.galaxy:
        // 채워진 타원
        final rect = Rect.fromCenter(
          center: center,
          width: size * 1.4,
          height: size * 0.72,
        );
        canvas.drawOval(rect, solidFill);
      case SkyMapObjectSymbolKind.openCluster:
        // 테두리 사각형 (범위 원과 구분)
        final half = size * 0.38;
        final rect = Rect.fromCenter(
          center: center,
          width: half * 2,
          height: half * 2,
        );
        canvas.drawRect(rect, lightFill);
        canvas.drawRect(rect, stroke);
      case SkyMapObjectSymbolKind.globularCluster:
        final rOuter = size * 0.45;
        final rInner = size * 0.22;
        canvas.drawCircle(center, rOuter, lightFill);
        canvas.drawCircle(center, rOuter, stroke);
        canvas.drawCircle(center, rInner, stroke);
      case SkyMapObjectSymbolKind.nebula:
        // 채워진 마름모
        final half = size * 0.42;
        final path = Path()
          ..moveTo(center.dx, center.dy - half)
          ..lineTo(center.dx + half, center.dy)
          ..lineTo(center.dx, center.dy + half)
          ..lineTo(center.dx - half, center.dy)
          ..close();
        canvas.drawPath(path, solidFill);
      case SkyMapObjectSymbolKind.planetaryNebula:
        _drawStar(canvas, center, size * 0.5, solidFill, stroke);
      case SkyMapObjectSymbolKind.point:
        final r = size * 0.28;
        canvas.drawCircle(center, r, solidFill);
    }
  }

  static void _drawStar(
    Canvas canvas,
    Offset center,
    double radius,
    Paint fill,
    Paint stroke,
  ) {
    const points = 5;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : radius * 0.42;
      final angle = -math.pi / 2 + i * math.pi / points;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter({required this.kind, required this.color});

  final SkyMapObjectSymbolKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    SkyMapObjectSymbolPainter.paint(
      canvas,
      center: Offset(size.width / 2, size.height / 2),
      kind: kind,
      color: color,
      size: math.min(size.width, size.height),
    );
  }

  @override
  bool shouldRepaint(covariant _SymbolPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}

/// 성도 좌상단 천체 종류 심볼 범례.
class SkyMapSymbolLegend extends StatelessWidget {
  const SkyMapSymbolLegend({super.key});

  static const _entries = <(SkyMapObjectSymbolKind, String)>[
    (SkyMapObjectSymbolKind.galaxy, '은하'),
    (SkyMapObjectSymbolKind.openCluster, '산개성단'),
    (SkyMapObjectSymbolKind.globularCluster, '구상성단'),
    (SkyMapObjectSymbolKind.nebula, '성운'),
    (SkyMapObjectSymbolKind.planetaryNebula, '행성상성운'),
  ];

  @override
  Widget build(BuildContext context) {
    const symbolColor = Color(0xFF9BE7FF);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _entries.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkyMapObjectSymbol(
                    kind: _entries[i].$1,
                    color: symbolColor,
                    size: 13,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _entries[i].$2,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
