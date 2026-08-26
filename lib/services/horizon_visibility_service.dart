import '../data/models/site_horizon_profile.dart';

/// 방위각별 최소 가시 고도를 원형 선형 보간으로 계산한다.
class HorizonVisibilityService {
  const HorizonVisibilityService();

  double minimumVisibleAltitude(SiteHorizonProfile profile, double azimuth) {
    if (!azimuth.isFinite || profile.points.isEmpty) return 0;

    // 저장 계층은 중복 방위각을 막지만, 계산 계층도 외부/향후 스캔 입력에
    // 안전하도록 마지막 값을 canonical 값으로 사용한다.
    final byAzimuth = <double, double>{};
    for (final point in profile.points) {
      if (!point.azimuth.isFinite || !point.minAltitude.isFinite) continue;
      byAzimuth[_normalize(point.azimuth)] = point.minAltitude.clamp(0, 90);
    }
    if (byAzimuth.isEmpty) return 0;

    final samples = byAzimuth.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (samples.length == 1) return samples.single.value;

    final target = _normalize(azimuth);
    for (final sample in samples) {
      if ((sample.key - target).abs() < 1e-9) return sample.value;
    }

    for (var index = 0; index < samples.length; index++) {
      final left = samples[index];
      final right = samples[(index + 1) % samples.length];
      final rightAzimuth = index == samples.length - 1
          ? right.key + 360
          : right.key;
      final adjustedTarget = index == samples.length - 1 && target < left.key
          ? target + 360
          : target;
      if (adjustedTarget < left.key || adjustedTarget > rightAzimuth) continue;

      final span = rightAzimuth - left.key;
      if (span <= 0) return left.value;
      final ratio = (adjustedTarget - left.key) / span;
      return left.value + (right.value - left.value) * ratio;
    }

    return 0;
  }

  bool isVisible({
    required SiteHorizonProfile profile,
    required double azimuth,
    required double altitude,
  }) {
    if (!azimuth.isFinite || !altitude.isFinite) return false;
    final normalized = _normalize(azimuth);
    if (profile.blockedRanges.any((range) => range.contains(normalized))) {
      return false;
    }
    return altitude >= minimumVisibleAltitude(profile, normalized);
  }

  double _normalize(double azimuth) {
    final value = azimuth % 360;
    return value < 0 ? value + 360 : value;
  }
}
