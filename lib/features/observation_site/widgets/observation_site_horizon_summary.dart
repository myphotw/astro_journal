import 'package:flutter/material.dart';

import '../../../data/models/observation_site.dart';
import '../../../data/models/site_horizon_profile.dart';
import '../../../services/horizon_visibility_service.dart';
import 'horizon_visibility_overview.dart';

class ObservationSiteHorizonSummary extends StatelessWidget {
  const ObservationSiteHorizonSummary({super.key, required this.site});

  final ObservationSite site;

  @override
  Widget build(BuildContext context) {
    final profile = SiteHorizonProfile(
      points: site.horizonPoints,
      blockedRanges: site.blockedAzimuthRanges,
    );
    const visibility = HorizonVisibilityService();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('촬영 가능 시야', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: '실제 시야',
                value: profile.hasRestrictions ? '등록됨' : '제한 없음',
              ),
            ),
            Expanded(
              child: _Metric(
                label: '방향 지점',
                value: '${site.horizonPoints.length}개',
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
        HorizonVisibilityOverview(
          points: site.horizonPoints,
          blockedRanges: site.blockedAzimuthRanges,
        ),
        if (site.horizonPoints.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children:
                const <(double, String)>[
                  (0, '북'),
                  (45, '북동'),
                  (90, '동'),
                  (135, '남동'),
                  (180, '남'),
                  (225, '남서'),
                  (270, '서'),
                  (315, '북서'),
                ].map((direction) {
                  final altitude = visibility.minimumVisibleAltitude(
                    profile,
                    direction.$1,
                  );
                  return Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${direction.$2} ${altitude.round()}°'),
                  );
                }).toList(),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          site.blockedAzimuthRanges.isEmpty
              ? '촬영 가능 방향: 360° 전체'
              : '막힌 방향: ${site.blockedAzimuthRanges.map((range) => '${range.startAzimuth.toStringAsFixed(0)}°~${range.endAzimuth.toStringAsFixed(0)}°').join(', ')}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          site.horizonPoints.isEmpty
              ? '방향별 고도 제한이 없습니다.'
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
