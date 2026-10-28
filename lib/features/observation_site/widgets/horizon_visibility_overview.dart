import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/blocked_azimuth_range.dart';
import '../../../data/models/horizon_point.dart';
import '../../../data/models/site_horizon_profile.dart';
import '../../../services/horizon_visibility_service.dart';

enum HorizonBoundaryKind { minimum, maximum }

enum BlockedRangeBoundaryKind { start, end }

@immutable
class HorizonBlockedRangeSelection {
  const HorizonBlockedRangeSelection({
    required this.rangeId,
    required this.boundary,
    required this.azimuth,
  });

  final String rangeId;
  final BlockedRangeBoundaryKind boundary;
  final double azimuth;
}

@immutable
class HorizonGraphSelection {
  const HorizonGraphSelection({
    required this.azimuth,
    required this.boundary,
    this.pointId,
  });

  final String? pointId;
  final double azimuth;
  final HorizonBoundaryKind boundary;

  bool get isExistingPoint => pointId != null;
}

class HorizonVisibilityOverview extends StatefulWidget {
  const HorizonVisibilityOverview({
    super.key,
    required this.points,
    required this.blockedRanges,
    this.editable = false,
    this.selection,
    this.blockedSelection,
    this.onSelectionChanged,
    this.onAltitudeChanged,
    this.onBlockedSelectionChanged,
    this.onBlockedAzimuthChanged,
  });

  final List<HorizonPoint> points;
  final List<BlockedAzimuthRange> blockedRanges;
  final bool editable;
  final HorizonGraphSelection? selection;
  final HorizonBlockedRangeSelection? blockedSelection;
  final ValueChanged<HorizonGraphSelection>? onSelectionChanged;
  final void Function(HorizonGraphSelection selection, double altitude)?
  onAltitudeChanged;
  final ValueChanged<HorizonBlockedRangeSelection>? onBlockedSelectionChanged;
  final void Function(HorizonBlockedRangeSelection selection, double azimuth)?
  onBlockedAzimuthChanged;

  @override
  State<HorizonVisibilityOverview> createState() =>
      _HorizonVisibilityOverviewState();
}

class _HorizonVisibilityOverviewState extends State<HorizonVisibilityOverview> {
  HorizonGraphSelection? _activeDragSelection;
  HorizonBlockedRangeSelection? _activeBlockedDragSelection;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final data = HorizonVisibilityProfileData(
      points: widget.points,
      blockedRanges: widget.blockedRanges,
    );
    return Column(
      key: const Key('horizon-visibility-profile'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 168,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const plotLeft = 32.0;
              const plotRight = 4.0;
              const plotTop = 6.0;
              const plotBottom = 26.0;
              const yLabelWidth = 28.0;
              const yLabelHeight = 16.0;
              const xLabelWidth = 52.0;
              const xLabelHeight = 22.0;
              final plotWidth = math.max(
                0.0,
                constraints.maxWidth - plotLeft - plotRight,
              );
              final plotHeight = 168 - plotTop - plotBottom;
              final labelStyle = Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontSize: 10);
              const yTicks = [90.0, 60.0, 30.0, 0.0];
              const xTicks = [
                (azimuth: 0.0, label: '북 0°'),
                (azimuth: 90.0, label: '동 90°'),
                (azimuth: 180.0, label: '남 180°'),
                (azimuth: 270.0, label: '서 270°'),
                (azimuth: 360.0, label: '북 360°'),
              ];

              return Stack(
                children: [
                  Positioned(
                    left: plotLeft,
                    right: plotRight,
                    top: plotTop,
                    bottom: plotBottom,
                    child: Listener(
                      onPointerDown: widget.editable
                          ? (event) => _beginBlockedPointerDrag(
                              event.localPosition,
                              Size(plotWidth, plotHeight),
                              data,
                            )
                          : null,
                      onPointerMove: widget.editable
                          ? (event) => _updateBlockedPointerDrag(
                              event.localPosition,
                              Size(plotWidth, plotHeight),
                            )
                          : null,
                      onPointerUp: widget.editable
                          ? (_) => _endBlockedPointerDrag()
                          : null,
                      onPointerCancel: widget.editable
                          ? (_) => _endBlockedPointerDrag()
                          : null,
                      child: GestureDetector(
                        key: widget.editable
                            ? const Key('editable-horizon-graph')
                            : null,
                        behavior: HitTestBehavior.opaque,
                        onTapDown: widget.editable
                            ? (details) => _selectAt(
                                details.localPosition,
                                Size(plotWidth, plotHeight),
                                data,
                              )
                            : null,
                        onPanDown: widget.editable
                            ? (details) => _beginDragAt(
                                details.localPosition,
                                Size(plotWidth, plotHeight),
                                data,
                              )
                            : null,
                        onPanUpdate: widget.editable
                            ? (details) => _dragTo(
                                details.localPosition,
                                Size(plotWidth, plotHeight),
                              )
                            : null,
                        onPanEnd: widget.editable ? (_) => _endDrag() : null,
                        onPanCancel: widget.editable ? _endDrag : null,
                        child: CustomPaint(
                          key: const Key(
                            'observation-site-horizon-visualization',
                          ),
                          painter: HorizonVisibilityProfilePainter(
                            data: data,
                            visibleColor: colors.primary,
                            unavailableColor: colors.errorContainer,
                            gridColor: colors.outlineVariant,
                            editable: widget.editable,
                            selection: widget.selection,
                            blockedSelection: widget.blockedSelection,
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (final altitude in yTicks)
                    Positioned(
                      left: 0,
                      width: yLabelWidth,
                      height: yLabelHeight,
                      top:
                          (plotTop +
                                  plotHeight * (1 - altitude / 90) -
                                  yLabelHeight / 2)
                              .clamp(0.0, 168 - yLabelHeight)
                              .toDouble(),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${altitude.round()}°',
                          maxLines: 1,
                          style: labelStyle,
                        ),
                      ),
                    ),
                  for (var index = 0; index < xTicks.length; index++)
                    Positioned(
                      left: switch (index) {
                        0 => plotLeft,
                        4 => plotLeft + plotWidth - xLabelWidth,
                        _ =>
                          plotLeft +
                              plotWidth * xTicks[index].azimuth / 360 -
                              xLabelWidth / 2,
                      },
                      bottom: 0,
                      width: xLabelWidth,
                      height: xLabelHeight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: switch (index) {
                          0 => Alignment.centerLeft,
                          4 => Alignment.centerRight,
                          _ => Alignment.center,
                        },
                        child: Text(xTicks[index].label, style: labelStyle),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        HorizonVisibilityLegend(
          visibleColor: colors.primary,
          unavailableColor: colors.errorContainer,
        ),
      ],
    );
  }

  void _selectAt(
    Offset position,
    Size size,
    HorizonVisibilityProfileData data,
  ) {
    final blockedSelection = _blockedSelectionAt(position, size, data);
    if (blockedSelection != null) {
      _activeDragSelection = null;
      _activeBlockedDragSelection = blockedSelection;
      widget.onBlockedSelectionChanged?.call(blockedSelection);
      return;
    }
    final selection = _selectionAt(position, size, data);
    _activeBlockedDragSelection = null;
    _activeDragSelection = selection;
    widget.onSelectionChanged?.call(selection);
  }

  void _beginDragAt(
    Offset position,
    Size size,
    HorizonVisibilityProfileData data,
  ) {
    if (_activeBlockedDragSelection != null) return;
    _selectAt(position, size, data);
  }

  void _beginBlockedPointerDrag(
    Offset position,
    Size size,
    HorizonVisibilityProfileData data,
  ) {
    final selection = _blockedSelectionAt(position, size, data);
    if (selection == null) return;
    _activeDragSelection = null;
    _activeBlockedDragSelection = selection;
    widget.onBlockedSelectionChanged?.call(selection);
  }

  void _updateBlockedPointerDrag(Offset position, Size size) {
    if (_activeBlockedDragSelection == null) return;
    _dragTo(position, size);
  }

  void _endBlockedPointerDrag() {
    _activeBlockedDragSelection = null;
  }

  void _endDrag() {
    _activeDragSelection = null;
    _activeBlockedDragSelection = null;
  }

  HorizonBlockedRangeSelection? _blockedSelectionAt(
    Offset position,
    Size size,
    HorizonVisibilityProfileData data,
  ) {
    const hitRadius = 28.0;
    final selected = widget.blockedSelection;
    if (selected != null) {
      final selectedRange = data.blockedRanges
          .cast<BlockedAzimuthRange?>()
          .firstWhere(
            (range) => range?.id == selected.rangeId,
            orElse: () => null,
          );
      if (selectedRange != null) {
        final azimuth = selected.boundary == BlockedRangeBoundaryKind.start
            ? selectedRange.startAzimuth
            : selectedRange.endAzimuth;
        if (_distanceToBlockedHandle(position, size, azimuth) <= hitRadius) {
          return HorizonBlockedRangeSelection(
            rangeId: selectedRange.id,
            boundary: selected.boundary,
            azimuth: azimuth,
          );
        }
      }
    }

    HorizonBlockedRangeSelection? nearest;
    var nearestDistance = double.infinity;
    for (final range in data.blockedRanges) {
      for (final candidate in [
        (boundary: BlockedRangeBoundaryKind.start, azimuth: range.startAzimuth),
        (boundary: BlockedRangeBoundaryKind.end, azimuth: range.endAzimuth),
      ]) {
        final distance = _distanceToBlockedHandle(
          position,
          size,
          candidate.azimuth,
        );
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = HorizonBlockedRangeSelection(
            rangeId: range.id,
            boundary: candidate.boundary,
            azimuth: candidate.azimuth,
          );
        }
      }
    }
    return nearestDistance <= hitRadius ? nearest : null;
  }

  double _distanceToBlockedHandle(Offset position, Size size, double azimuth) {
    final handleY = _blockedHandleY(size);
    return _blockedHandleXPositions(size, azimuth)
        .map(
          (x) => math.sqrt(
            math.pow(position.dx - x, 2) + math.pow(position.dy - handleY, 2),
          ),
        )
        .reduce(math.min);
  }

  HorizonGraphSelection _selectionAt(
    Offset position,
    Size size,
    HorizonVisibilityProfileData data,
  ) {
    final normalizedX = position.dx.clamp(0.0, size.width);
    final touchedAzimuth = normalizedX >= size.width
        ? 0.0
        : 360 * normalizedX / size.width;
    final touchedAltitude = _altitudeForY(position.dy, size.height);
    HorizonPoint? nearestPoint;
    HorizonBoundaryKind? nearestBoundary;
    var nearestDistance = double.infinity;

    for (final point in data.points) {
      final pointX = size.width * _normalizeAzimuth(point.azimuth) / 360;
      final directXDistance = (position.dx - pointX).abs();
      final xDistance = math.min(
        directXDistance,
        (size.width - directXDistance).abs(),
      );
      final minY = _yForAltitude(point.minAltitude, size.height);
      final maxY = _yForAltitude(point.maxAltitude ?? 90, size.height);
      for (final candidate in [
        (boundary: HorizonBoundaryKind.minimum, y: minY),
        (boundary: HorizonBoundaryKind.maximum, y: maxY),
      ]) {
        final distance = math.sqrt(
          xDistance * xDistance +
              math.pow(position.dy - candidate.y, 2).toDouble(),
        );
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestPoint = point;
          nearestBoundary = candidate.boundary;
        }
      }
    }

    if (nearestPoint != null && nearestDistance <= 30) {
      return HorizonGraphSelection(
        pointId: nearestPoint.id,
        azimuth: nearestPoint.azimuth,
        boundary: nearestBoundary!,
      );
    }

    final minimum = data.minAltitudeAt(touchedAzimuth);
    final maximum = data.maxAltitudeAt(touchedAzimuth);
    return HorizonGraphSelection(
      azimuth: touchedAzimuth.roundToDouble() % 360,
      boundary:
          (touchedAltitude - minimum).abs() <= (touchedAltitude - maximum).abs()
          ? HorizonBoundaryKind.minimum
          : HorizonBoundaryKind.maximum,
    );
  }

  void _dragTo(Offset position, Size size) {
    final blockedSelection = _activeBlockedDragSelection;
    if (blockedSelection != null) {
      final azimuth = _azimuthForX(position.dx, size.width);
      final updated = HorizonBlockedRangeSelection(
        rangeId: blockedSelection.rangeId,
        boundary: blockedSelection.boundary,
        azimuth: azimuth,
      );
      _activeBlockedDragSelection = updated;
      widget.onBlockedAzimuthChanged?.call(updated, azimuth);
      return;
    }
    final selection = _activeDragSelection;
    if (selection == null || !selection.isExistingPoint) return;
    final altitude = _altitudeForY(position.dy, size.height).roundToDouble();
    widget.onAltitudeChanged?.call(selection, altitude);
  }

  double _altitudeForY(double y, double height) =>
      (90 * (1 - y.clamp(0.0, height) / height)).clamp(0.0, 90.0);

  double _yForAltitude(num altitude, double height) =>
      height * (1 - altitude / 90);

  double _normalizeAzimuth(double azimuth) {
    final normalized = azimuth % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }
}

double _azimuthForX(double x, double width) {
  if (width <= 0) return 0;
  final degrees = (360 * x.clamp(0.0, width) / width).round();
  return (degrees % 360).toDouble();
}

double _blockedHandleY(Size size) => math.max(0, size.height - 12);

Iterable<double> _blockedHandleXPositions(Size size, double azimuth) sync* {
  final normalized = ((azimuth % 360) + 360) % 360;
  if (normalized == 0) {
    yield 0;
    yield size.width;
    return;
  }
  yield size.width * normalized / 360;
}

class HorizonVisibilityProfileData {
  HorizonVisibilityProfileData({
    required List<HorizonPoint> points,
    required List<BlockedAzimuthRange> blockedRanges,
  }) : points = List.unmodifiable(points),
       blockedRanges = List.unmodifiable(blockedRanges),
       _profile = SiteHorizonProfile(
         points: List.unmodifiable(points),
         blockedRanges: List.unmodifiable(blockedRanges),
       );

  final List<HorizonPoint> points;
  final List<BlockedAzimuthRange> blockedRanges;
  final SiteHorizonProfile _profile;

  double minAltitudeAt(double azimuth) => const HorizonVisibilityService()
      .minimumVisibleAltitude(_profile, azimuth);

  double maxAltitudeAt(double azimuth) => const HorizonVisibilityService()
      .maximumVisibleAltitude(_profile, azimuth);

  bool isBlocked(double azimuth) {
    final normalized = ((azimuth % 360) + 360) % 360;
    return blockedRanges.any((range) => range.contains(normalized));
  }
}

class HorizonVisibilityProfilePainter extends CustomPainter {
  const HorizonVisibilityProfilePainter({
    required this.data,
    required this.visibleColor,
    required this.unavailableColor,
    required this.gridColor,
    this.editable = false,
    this.selection,
    this.blockedSelection,
  });

  final HorizonVisibilityProfileData data;
  final Color visibleColor;
  final Color unavailableColor;
  final Color gridColor;
  final bool editable;
  final HorizonGraphSelection? selection;
  final HorizonBlockedRangeSelection? blockedSelection;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()..color = unavailableColor.withValues(alpha: 0.48),
    );

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    for (final altitude in const [0.0, 30.0, 60.0, 90.0]) {
      final y = _yForAltitude(altitude, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (final azimuth in const [0.0, 90.0, 180.0, 270.0, 360.0]) {
      final x = size.width * azimuth / 360;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final visiblePaint = Paint()
      ..color = visibleColor.withValues(alpha: 0.42)
      ..strokeWidth = 1.5;
    final minPaint = Paint()
      ..color = visibleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final maxPaint = Paint()
      ..color = visibleColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final minPath = Path();
    final maxPath = Path();
    var minStarted = false;
    var maxStarted = false;
    final columns = math.max(1, size.width.ceil());

    for (var column = 0; column <= columns; column++) {
      final x = size.width * column / columns;
      final azimuth = 360 * column / columns;
      if (data.isBlocked(azimuth)) {
        minStarted = false;
        maxStarted = false;
        continue;
      }
      final minAltitude = data.minAltitudeAt(azimuth).clamp(0.0, 90.0);
      final maxAltitude = data.maxAltitudeAt(azimuth).clamp(0.0, 90.0);
      if (maxAltitude < minAltitude) {
        minStarted = false;
        maxStarted = false;
        continue;
      }
      final minY = _yForAltitude(minAltitude, size.height);
      final maxY = _yForAltitude(maxAltitude, size.height);
      canvas.drawLine(Offset(x, maxY), Offset(x, minY), visiblePaint);
      if (minStarted) {
        minPath.lineTo(x, minY);
      } else {
        minPath.moveTo(x, minY);
        minStarted = true;
      }
      if (maxStarted) {
        maxPath.lineTo(x, maxY);
      } else {
        maxPath.moveTo(x, maxY);
        maxStarted = true;
      }
    }
    canvas.drawPath(minPath, minPaint);
    canvas.drawPath(maxPath, maxPaint);
    if (editable) {
      _paintMeasurementPoints(canvas, size);
      _paintBlockedBoundaries(canvas, size);
      _paintSelection(canvas, size);
    }
    canvas.drawRect(
      bounds,
      Paint()
        ..color = gridColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  double _yForAltitude(num altitude, double height) =>
      height * (1 - altitude / 90);

  void _paintMeasurementPoints(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = visibleColor
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = visibleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final point in data.points) {
      final x = size.width * _normalizeAzimuth(point.azimuth) / 360;
      final xPositions = point.azimuth == 0 ? <double>[0, size.width] : [x];
      for (final markerX in xPositions) {
        canvas.drawCircle(
          Offset(markerX, _yForAltitude(point.minAltitude, size.height)),
          3.2,
          fill,
        );
        if (point.maxAltitude != null) {
          canvas.drawCircle(
            Offset(markerX, _yForAltitude(point.maxAltitude!, size.height)),
            3.2,
            outline,
          );
        }
      }
    }
  }

  void _paintBlockedBoundaries(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = unavailableColor.withValues(alpha: 0.9)
      ..strokeWidth = 1.5;
    final fillPaint = Paint()
      ..color = unavailableColor
      ..style = PaintingStyle.fill;
    final selectedOutline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final handleY = _blockedHandleY(size);

    for (final range in data.blockedRanges) {
      for (final candidate in [
        (boundary: BlockedRangeBoundaryKind.start, azimuth: range.startAzimuth),
        (boundary: BlockedRangeBoundaryKind.end, azimuth: range.endAzimuth),
      ]) {
        final selected =
            blockedSelection?.rangeId == range.id &&
            blockedSelection?.boundary == candidate.boundary;
        for (final x in _blockedHandleXPositions(size, candidate.azimuth)) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
          canvas.drawCircle(Offset(x, handleY), selected ? 8 : 6, fillPaint);
          if (selected) {
            canvas.drawCircle(Offset(x, handleY), 10, selectedOutline);
          }
        }
      }
    }
  }

  void _paintSelection(Canvas canvas, Size size) {
    final current = selection;
    if (current == null) return;
    final point = current.pointId == null
        ? null
        : data.points.cast<HorizonPoint?>().firstWhere(
            (item) => item?.id == current.pointId,
            orElse: () => null,
          );
    final azimuth = point?.azimuth ?? current.azimuth;
    final altitude = switch (current.boundary) {
      HorizonBoundaryKind.minimum =>
        point?.minAltitude ?? data.minAltitudeAt(azimuth),
      HorizonBoundaryKind.maximum =>
        point?.maxAltitude ?? data.maxAltitudeAt(azimuth),
    };
    final center = Offset(
      size.width * _normalizeAzimuth(azimuth) / 360,
      _yForAltitude(altitude, size.height),
    );
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  double _normalizeAzimuth(double azimuth) {
    final normalized = azimuth % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  @override
  bool shouldRepaint(covariant HorizonVisibilityProfilePainter oldDelegate) =>
      oldDelegate.data.points != data.points ||
      oldDelegate.data.blockedRanges != data.blockedRanges ||
      oldDelegate.visibleColor != visibleColor ||
      oldDelegate.unavailableColor != unavailableColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.editable != editable ||
      oldDelegate.selection != selection ||
      oldDelegate.blockedSelection != blockedSelection;
}

class HorizonVisibilityLegend extends StatelessWidget {
  const HorizonVisibilityLegend({
    super.key,
    required this.visibleColor,
    required this.unavailableColor,
  });

  final Color visibleColor;
  final Color unavailableColor;

  @override
  Widget build(BuildContext context) => Wrap(
    key: const Key('horizon-visibility-legend'),
    spacing: 12,
    runSpacing: 6,
    children: [
      _LegendEntry(
        key: const Key('horizon-legend-visible'),
        color: visibleColor.withValues(alpha: 0.42),
        label: '보이는 하늘 영역',
      ),
      _LegendEntry(
        key: const Key('horizon-legend-blocked'),
        color: unavailableColor.withValues(alpha: 0.48),
        label: '가려진 영역',
      ),
    ],
  );
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 16,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}
