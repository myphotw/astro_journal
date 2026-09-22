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
  }) {
    final reasons = <RecommendationReason>[];

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
    final objectRa = CelestialPositionService.parseRaHours(ra);
    if (objectRa == null) return 0;
    final dist = _raDistance(optimalRa, objectRa);
    return math.max(0.0, 1 - dist / 12.0) * 40;
  }

  static double _raDistance(double optimal, double objectRa) {
    var diff = (objectRa - optimal).abs();
    if (diff > 12) diff = 24 - diff;
    return diff;
  }
}
