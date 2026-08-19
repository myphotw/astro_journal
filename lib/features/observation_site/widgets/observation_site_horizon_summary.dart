import 'package:flutter/material.dart';

import '../../../data/models/blocked_azimuth_range.dart';
import '../../../data/models/observation_site.dart';

class ObservationSiteHorizonSummary extends StatelessWidget {
  const ObservationSiteHorizonSummary({super.key, required this.site});

  final ObservationSite site;

  @override
  Widget build(BuildContext context) {
    final minimums = <double>[
      site.defaultMinAltitude,
      ...site.horizonPoints.map((point) => point.minAltitude),
    ];
    final maximums = <double>[
      if (site.defaultMaxAltitude != null) site.defaultMaxAltitude!,
      ...site.horizonPoints
          .where((point) => point.maxAltitude != null)
          .map((point) => point.maxAltitude!),
    ];
    final min = minimums.reduce((a, b) => a < b ? a : b);
    final max = maximums.isEmpty
        ? null
        : maximums.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('촬영 가능 시야', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: '최소 고도',
                value: '${min.toStringAsFixed(0)}°',
              ),
            ),
            Expanded(
              child: _Metric(
                label: '최대 고도',
                value: max == null ? '제한 없음' : '${max.toStringAsFixed(0)}°',
              ),
            ),
            Expanded(
              child: _Metric(
                label: '막힌 방향',
                value: '${site.blockedAzimuthRanges.length}개',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _AzimuthBar(site: site),
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
        const SizedBox(height: 6),
        Text(
          site.blockedAzimuthRanges.isEmpty
              ? '촬영 가능 방향: 360° 전체'
              : '막힌 방향: ${site.blockedAzimuthRanges.map((range) => '${range.startAzimuth.toStringAsFixed(0)}°~${range.endAzimuth.toStringAsFixed(0)}°').join(', ')}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          site.horizonPoints.isEmpty
              ? '기본 고도 기준을 사용합니다.'
              : '방향별 고도 ${site.horizonPoints.length}개가 저장되어 있습니다.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        Text(
          '저장된 방향·고도를 단순화한 대략적인 요약입니다.',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      Text(value, style: Theme.of(context).textTheme.titleSmall),
    ],
  );
}

class _AzimuthBar extends StatelessWidget {
  const _AzimuthBar({required this.site});

  final ObservationSite site;

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
            for (final range in site.blockedAzimuthRanges)
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
            for (final point in site.horizonPoints)
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
