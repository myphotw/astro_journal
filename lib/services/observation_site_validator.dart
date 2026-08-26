import '../data/models/blocked_azimuth_range.dart';
import '../data/models/horizon_point.dart';
import '../data/models/observation_site.dart';

abstract final class ObservationSiteValidator {
  static void validate(ObservationSite site) {
    if (site.name.trim().isEmpty) {
      throw ArgumentError.value(site.name, 'name', '관측지 이름은 필수입니다.');
    }
    _range(site.latitude, -90, 90, 'latitude', '위도');
    _range(site.longitude, -180, 180, 'longitude', '경도');
    if (site.bortle != null && (site.bortle! < 1 || site.bortle! > 9)) {
      throw ArgumentError.value(site.bortle, 'bortle', 'Bortle은 1~9여야 합니다.');
    }
    _altitudes(site.defaultMinAltitude, site.defaultMaxAltitude);

    final azimuths = <double>{};
    for (final point in site.horizonPoints) {
      validateHorizonPoint(point, expectedSiteId: site.id);
      if (!azimuths.add(point.azimuth)) {
        throw ArgumentError('같은 방위각의 Horizon 지점을 중복 저장할 수 없습니다.');
      }
    }
    for (final range in site.blockedAzimuthRanges) {
      validateBlockedRange(range, expectedSiteId: site.id);
    }
  }

  static void validateHorizonPoint(
    HorizonPoint point, {
    String? expectedSiteId,
  }) {
    if (expectedSiteId != null && point.observationSiteId != expectedSiteId) {
      throw ArgumentError('Horizon 지점의 관측지 ID가 일치하지 않습니다.');
    }
    _azimuth(point.azimuth, 'azimuth');
    _altitudes(point.minAltitude, point.maxAltitude);
  }

  static void validateBlockedRange(
    BlockedAzimuthRange range, {
    String? expectedSiteId,
  }) {
    if (expectedSiteId != null && range.observationSiteId != expectedSiteId) {
      throw ArgumentError('차단 구간의 관측지 ID가 일치하지 않습니다.');
    }
    _azimuth(range.startAzimuth, 'startAzimuth');
    _azimuth(range.endAzimuth, 'endAzimuth');
  }

  static void _azimuth(double value, String name) {
    if (!value.isFinite || value < 0 || value >= 360) {
      throw ArgumentError.value(value, name, '방위각은 0 이상 360 미만이어야 합니다.');
    }
  }

  static void _altitudes(double min, double? max) {
    _range(min, -90, 90, 'minAltitude', '최소 고도');
    if (max != null) {
      _range(max, -90, 90, 'maxAltitude', '최대 고도');
      if (max < min) {
        throw ArgumentError('최대 고도는 최소 고도 이상이어야 합니다.');
      }
    }
  }

  static void _range(
    double value,
    double min,
    double max,
    String name,
    String label,
  ) {
    if (!value.isFinite || value < min || value > max) {
      throw ArgumentError.value(value, name, '$label 값의 범위가 올바르지 않습니다.');
    }
  }
}
