import 'blocked_azimuth_range.dart';
import 'horizon_point.dart';

/// 관측지의 물리적인 하늘 가림 정보를 추천/스케줄 계산에 전달하는 불변 스냅샷.
///
/// 수동 편집과 향후 카메라 스캔은 모두 같은 [HorizonPoint] 구조를 사용한다.
class SiteHorizonProfile {
  const SiteHorizonProfile({
    this.points = const [],
    this.blockedRanges = const [],
  });

  final List<HorizonPoint> points;
  final List<BlockedAzimuthRange> blockedRanges;

  bool get hasRestrictions => points.isNotEmpty || blockedRanges.isNotEmpty;
}
