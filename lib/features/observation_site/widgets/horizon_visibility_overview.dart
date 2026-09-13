import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/blocked_azimuth_range.dart';
import '../../../data/models/horizon_point.dart';
import '../../../data/models/site_horizon_profile.dart';
import '../../../services/horizon_visibility_service.dart';

class HorizonVisibilityOverview extends StatelessWidget {
  const HorizonVisibilityOverview({
    super.key,
    required this.points,
    required this.blockedRanges,
  });

  final List<HorizonPoint> points;
  final List<BlockedAzimuthRange> blockedRanges;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final data = HorizonVisibilityProfileData(
      points: points,
      blockedRanges: blockedRanges,
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
              final labelStyle = Theme.of(context).textTheme.labelSmall
                  ?.copyWith(fontSize: 10);
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
                    child: CustomPaint(
                      key: const Key(
                        'observation-site-horizon-visualization',
                      ),
                      painter: HorizonVisibilityProfilePainter(
                        data: data,
                        visibleColor: colors.primary,
                        unavailableColor: colors.errorContainer,
                        gridColor: colors.outlineVariant,
                      ),
                    ),
                  ),
                  for (final altitude in yTicks)
                    Positioned(
                      left: 0,
                      width: yLabelWidth,
                      height: yLabelHeight,
                      top: (plotTop +
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
                        _ => plotLeft +
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

  double minAltitudeAt(double azimuth) =>
      const HorizonVisibilityService().minimumVisibleAltitude(
        _profile,
        azimuth,
      );

  double maxAltitudeAt(double azimuth) =>
      const HorizonVisibilityService().maximumVisibleAltitude(
        _profile,
        azimuth,
      );

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
  });

  final HorizonVisibilityProfileData data;
  final Color visibleColor;
  final Color unavailableColor;
  final Color gridColor;

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

  @override
  bool shouldRepaint(covariant HorizonVisibilityProfilePainter oldDelegate) =>
      oldDelegate.data.points != data.points ||
      oldDelegate.data.blockedRanges != data.blockedRanges ||
      oldDelegate.visibleColor != visibleColor ||
      oldDelegate.unavailableColor != unavailableColor ||
      oldDelegate.gridColor != gridColor;
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
  const _LegendEntry({
    super.key,
    required this.color,
    required this.label,
  });

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
