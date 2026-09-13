import 'package:flutter/material.dart';

import '../../../data/models/horizon_point.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/models/site_horizon_profile.dart';
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
                label: '차단 구간',
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
        const SizedBox(height: 10),
        Semantics(
          container: true,
          label: '시야 범위 요약',
          child: Column(
            key: const Key('horizon-visibility-summary'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '촬영 가능 방향: ${_availableAzimuthLabel(site)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                site.horizonPoints.isEmpty
                    ? '방향별 고도 제한이 없습니다.'
                    : _altitudeLabel(site),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '그래프는 방향별로 실제 보이는 고도 범위를 나타냅니다.',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }

  String _availableAzimuthLabel(ObservationSite site) {
    final ranges = site.blockedAzimuthRanges;
    if (ranges.isEmpty) return '360° 전체';
    if (ranges.length == 1 &&
        ranges.single.source == HorizonDataSource.cameraScan) {
      final blocked = ranges.single;
      final start = (blocked.endAzimuth + 1) % 360;
      final end = (blocked.startAzimuth - 1 + 360) % 360;
      return '${start.toStringAsFixed(0)}° ~ ${end.toStringAsFixed(0)}°';
    }
    return '차단 구간 ${ranges.length}개 제외';
  }

  String _altitudeLabel(ObservationSite site) {
    final minimums = site.horizonPoints.map((point) => point.minAltitude);
    final minLower = minimums.reduce((a, b) => a < b ? a : b);
    final maxLower = minimums.reduce((a, b) => a > b ? a : b);
    final maximums = site.horizonPoints.map(
      (point) => point.maxAltitude ?? 90,
    );
    final minUpper = maximums.reduce((a, b) => a < b ? a : b);
    final maxUpper = maximums.reduce((a, b) => a > b ? a : b);
    final lowerLabel = minLower == maxLower
        ? '${minLower.round()}°'
        : '${minLower.round()}°~${maxLower.round()}°';
    final upperLabel = minUpper >= 90 && maxUpper >= 90
        ? '제한 없음'
        : minUpper == maxUpper
        ? '${minUpper.round()}°'
        : '${minUpper.round()}°~${maxUpper.round()}°';
    return '하단 경계 $lowerLabel · 상단 경계 $upperLabel';
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
