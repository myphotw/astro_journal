import 'dart:math' as math;

import '../../data/models/catalog_object.dart';
import '../../data/models/object_observation_window.dart';
import '../../data/models/recommendation_reason.dart';
import '../celestial_position_service.dart';

abstract final class RecommendationReasonBuilder {
  static const _optimalRaByMonth = [7, 9, 11, 13, 15, 17, 19, 21, 23, 1, 3, 5];

  static List<RecommendationReason> build({
    required CatalogObject object,
    required ObjectObservationWindow window,
    required double moonSeparation,
    required double moonIllumination,
    required String season,
    required int month,
    int cloudCoverage = 0,
    double windSpeed = 0,
  }) {
    final reasons = <RecommendationReason>[];

    if (!object.captured) {
      reasons.add(
        const RecommendationReason(
          type: RecommendationReasonType.uncaptured,
          label: '✓ 미촬영 대상',
        ),
      );
    }

    if (window.isCurrentlyVisible) {
      reasons.add(
        const RecommendationReason(
          type: RecommendationReasonType.currentlyVisible,
          label: '✓ 현재 관측 가능',
        ),
      );
    }

    final optimal = window.optimalAltitude ?? window.peakAltitude;
    if (optimal != null) {
      reasons.add(
        RecommendationReason(
          type: RecommendationReasonType.currentAltitude,
          label: '✓ 최적 고도 ${optimal.round()}°',
        ),
      );
    }

    reasons.add(
      RecommendationReason(
        type: RecommendationReasonType.moonSeparation,
        label: '✓ 달과 거리 ${moonSeparation.round()}°',
      ),
    );

    if (cloudCoverage >= 0) {
      reasons.add(
        RecommendationReason(
          type: RecommendationReasonType.cloud,
          label: '✓ 구름 ${cloudCoverage.round()}%',
        ),
      );
    }

    if (windSpeed >= 0) {
      final windLabel = windSpeed == windSpeed.roundToDouble()
          ? '${windSpeed.round()}'
          : windSpeed.toStringAsFixed(1);
      reasons.add(
        RecommendationReason(
          type: RecommendationReasonType.wind,
          label: '✓ 풍속 ${windLabel}m/s',
        ),
      );
    }

    if (_seasonScore(month, object.ra) >= 20) {
      reasons.add(
        RecommendationReason(
          type: RecommendationReasonType.season,
          label: '✓ 현재 $season 추천 대상',
        ),
      );
    } else if (moonIllumination < 0.2) {
      reasons.add(
        const RecommendationReason(
          type: RecommendationReasonType.season,
          label: '✓ 달 영향 거의 없음',
        ),
      );
    }

    reasons.add(
      const RecommendationReason(
        type: RecommendationReasonType.settings,
        label: '✓ 관리자 설정 조건 만족',
      ),
    );

    if (window.totalObservableMinutes >= 60) {
      reasons.add(
        const RecommendationReason(
          type: RecommendationReasonType.observableTime,
          label: '✓ 관측 가능 시간 충족',
        ),
      );
    }

    return reasons;
  }

  static String seasonLabel(int month) {
    if (month >= 3 && month <= 5) return '봄';
    if (month >= 6 && month <= 8) return '여름';
    if (month >= 9 && month <= 11) return '가을';
    return '겨울';
  }

  static double _seasonScore(int month, String ra) {
    final optimalRa = _optimalRaByMonth[month - 1].toDouble();
    final dist = _raDistance(
      optimalRa,
      CelestialPositionService.parseRaHours(ra),
    );
    return math.max(0.0, 1 - dist / 12.0) * 40;
  }

  static double _raDistance(double optimal, double objectRa) {
    var diff = (objectRa - optimal).abs();
    if (diff > 12) diff = 24 - diff;
    return diff;
  }
}
