import 'package:flutter/material.dart';

import '../../../data/models/blocked_azimuth_range.dart';
import '../../../data/models/horizon_point.dart';

class HorizonVisibilityOverview extends StatelessWidget {
  const HorizonVisibilityOverview({
    super.key,
    required this.points,
    required this.blockedRanges,
    this.showUnmeasured = false,
  });

  final List<HorizonPoint> points;
  final List<BlockedAzimuthRange> blockedRanges;
  final bool showUnmeasured;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _AzimuthBar(points: points, blockedRanges: blockedRanges),
      const SizedBox(height: 6),
      HorizonVisibilityLegend(showUnmeasured: showUnmeasured),
      const SizedBox(height: 6),
      const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('북 0°'),
          Text('동 90°'),
          Text('남 180°'),
          Text('서 270°'),
          Text('북'),
        ],
      ),
    ],
  );
}

class HorizonVisibilityLegend extends StatelessWidget {
  const HorizonVisibilityLegend({super.key, this.showUnmeasured = false});

  final bool showUnmeasured;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      key: const Key('horizon-visibility-legend'),
      spacing: 12,
      runSpacing: 6,
      children: [
        _LegendEntry(
          key: const Key('horizon-legend-visible'),
          color: colors.surfaceContainerHighest,
          label: '촬영 가능 시야',
        ),
        _LegendEntry(
          key: const Key('horizon-legend-blocked'),
          color: colors.errorContainer,
          label: '장애물 / 촬영 불가 영역',
        ),
        _LegendEntry(
          key: const Key('horizon-legend-altitude'),
          color: colors.primary,
          label: '최소 가시 고도',
          marker: true,
        ),
        if (showUnmeasured)
          const _LegendEntry(
            key: Key('horizon-legend-unmeasured'),
            color: Colors.amber,
            label: '미측정 / 불확실',
          ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    super.key,
    required this.color,
    required this.label,
    this.marker = false,
  });

  final Color color;
  final String label;
  final bool marker;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: marker ? 4 : 16,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: marker ? null : BorderRadius.circular(3),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _AzimuthBar extends StatelessWidget {
  const _AzimuthBar({required this.points, required this.blockedRanges});

  final List<HorizonPoint> points;
  final List<BlockedAzimuthRange> blockedRanges;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    key: const Key('observation-site-horizon-visualization'),
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      return SizedBox(
        height: 28,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            for (final range in blockedRanges)
              for (final segment in _segments(range))
                Positioned(
                  left: width * segment.$1 / 360,
                  width: width * (segment.$2 - segment.$1) / 360,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                    ),
                  ),
                ),
            for (final point in points)
              Positioned(
                left: (width * point.azimuth / 360 - 2).clamp(0, width - 4),
                top: 2,
                bottom: 2,
                child: Container(
                  width: 4,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
      );
    },
  );

  List<(double, double)> _segments(BlockedAzimuthRange range) {
    if (range.startAzimuth <= range.endAzimuth) {
      return [(range.startAzimuth, range.endAzimuth)];
    }
    return [(range.startAzimuth, 360), (0, range.endAzimuth)];
  }
}
