import '../../core/constants/object_type.dart';
import '../../core/constants/surface_brightness_class.dart';
import '../../core/constants/visual_observation_weights.dart';
import '../../data/models/equipment.dart';
import '../../data/models/equipment_recommendation.dart';
import '../../data/models/eyepiece.dart';
import '../observation_score_service.dart';
import 'screen_fill_scoring.dart';
import 'visual_target_context.dart';
import 'visual_target_suitability.dart';

/// 안시 추천 점수·비추천·이유·아이피스 선택 (필터 없음 기준).
class VisualObservationScorer {
  const VisualObservationScorer();

  List<VisualEquipmentRecommendation> rankRecommendations({
    required VisualTargetContext context,
    required List<Equipment> visualEquipment,
  }) {
    if (visualEquipment.isEmpty) return const [];

    final hardBlock = _evaluateHardBlock(context, visualEquipment);
    if (hardBlock != null) return [hardBlock];

    final results = <VisualEquipmentRecommendation>[];
    for (final telescope in visualEquipment) {
      final aperture = telescope.apertureMm;
      final focalLength = telescope.focalLengthMm;
      final fRatio = telescope.fRatio;
      if (aperture == null ||
          focalLength == null ||
          aperture <= 0 ||
          focalLength <= 0 ||
          telescope.eyepieces.isEmpty) {
        continue;
      }

      for (final eyepiece in telescope.eyepieces) {
        final magnification = focalLength / eyepiece.focalLengthMm;
        final trueFov = eyepiece.afovDegrees / magnification;
        final framing = context.scoringFramingSize;
        final fillRatio = ScreenFillScoring.fillRatioFromSquareFov(
          targetWidthDegrees: framing.widthDegrees,
          targetHeightDegrees: framing.heightDegrees,
          fieldOfViewDegrees: trueFov,
        );
        if (fillRatio > ScreenFillScoring.idealMaxRatio) {
          continue;
        }

        results.add(
          _scoreCombo(
            context: context,
            telescope: telescope,
            eyepiece: eyepiece,
            apertureMm: aperture,
            fRatio: fRatio,
            includeEyepiece: true,
          ),
        );
      }
    }

    if (results.isEmpty) {
      return [
        VisualEquipmentRecommendation(
          equipment: visualEquipment.first,
          score: 10,
          starCount: 1,
          reason: '시야가 좁아 전체를 볼 수 없습니다.',
          isRecommended: false,
          screenFillPercent: 0,
        ),
      ];
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  VisualEquipmentRecommendation? bestRecommendation({
    required VisualTargetContext context,
    required List<Equipment> visualEquipment,
  }) {
    final ranked = rankRecommendations(
      context: context,
      visualEquipment: visualEquipment,
    );
    if (ranked.isEmpty) return null;
    return ranked.first;
  }

  VisualEquipmentRecommendation? _evaluateHardBlock(
    VisualTargetContext context,
    List<Equipment> visualEquipment,
  ) {
    final maxAperture = visualEquipment
        .map((e) => e.apertureMm ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);

    final brightness = context.visualSurfaceBrightness;
    final suitability = context.suitability;

    if (suitability.forceNotRecommended) {
      return _blocked(
        visualEquipment.first,
        reason: suitability.blockReason ?? '필터 없이 관측이 어렵습니다.',
      );
    }

    if (brightness.index >= SurfaceBrightnessClass.extremeDim.index &&
        maxAperture < VisualObservationWeights.minApertureExtremeDimMm) {
      return _blocked(
        visualEquipment.first,
        reason: '표면 밝기가 매우 낮습니다.',
      );
    }

    if (brightness.index >= SurfaceBrightnessClass.veryDim.index &&
        maxAperture < VisualObservationWeights.minApertureVeryDimMm) {
      return _blocked(
        visualEquipment.first,
        reason: '현재 장비로는 안시가 어렵습니다.',
      );
    }

    if (suitability.requiresWideField &&
        maxAperture < VisualObservationWeights.minApertureWideFieldMm) {
      return _blocked(
        visualEquipment.first,
        reason: '필터 없이 관측이 어렵습니다.',
      );
    }

    return null;
  }

  VisualEquipmentRecommendation _blocked(
    Equipment equipment, {
    required String reason,
  }) {
    return VisualEquipmentRecommendation(
      equipment: equipment,
      score: 12,
      starCount: 1,
      reason: reason,
      isRecommended: false,
      screenFillPercent: 0,
    );
  }

  VisualEquipmentRecommendation _scoreCombo({
    required VisualTargetContext context,
    required Equipment telescope,
    required Eyepiece eyepiece,
    required double apertureMm,
    required double? fRatio,
    bool includeEyepiece = false,
  }) {
    final focalLength = telescope.focalLengthMm!;
    final magnification = focalLength / eyepiece.focalLengthMm;
    final trueFov = eyepiece.afovDegrees / magnification;
    final framing = context.scoringFramingSize;
    final fillRatio = ScreenFillScoring.fillRatioFromSquareFov(
      targetWidthDegrees: framing.widthDegrees,
      targetHeightDegrees: framing.heightDegrees,
      fieldOfViewDegrees: trueFov,
    );
    final objectType = context.scoringObjectType;

    final surfaceScore = VisualObservationWeights.surfaceBrightnessScore(
      context.visualSurfaceBrightness,
    );
    final typeScore = VisualObservationWeights.objectTypeScore(objectType);
    final magnitudeScore = VisualObservationWeights.magnitudeScore(
      context.parsedMagnitude,
    );
    final sizeScore = _sizeFitScore(
      fillRatio,
      objectType,
      idealRatioOverride: context.suitability.observationBasis ==
              VisualObservationBasis.centralOpenCluster
          ? 0.12
          : null,
    );
    final telescopeScore = _telescopeScore(
      apertureMm: apertureMm,
      fRatio: fRatio,
      brightness: context.visualSurfaceBrightness,
    );

    var total = surfaceScore * VisualObservationWeights.surfaceBrightnessWeight +
        typeScore * VisualObservationWeights.objectTypeWeight +
        magnitudeScore * VisualObservationWeights.magnitudeWeight +
        sizeScore * VisualObservationWeights.sizeFitWeight +
        telescopeScore * VisualObservationWeights.telescopeWeight;

    if (context.suitability.tier == VisualSuitabilityTier.high) {
      total = (total * 1.08).clamp(0, 100);
    } else if (context.suitability.tier == VisualSuitabilityTier.low) {
      total = (total * 0.65).clamp(0, 100);
    }

    final penalty = context.suitability.noFilterPenalty;
    if (penalty < 1.0) {
      total = (total * penalty).clamp(0, 100);
    }

    if (context.suitability.observationBasis ==
        VisualObservationBasis.centralOpenCluster) {
      total = total.clamp(0, 52);
    }

    final isRecommended = fillRatio <= ScreenFillScoring.idealMaxRatio &&
        total >= VisualObservationWeights.recommendThreshold;
    final reason = _reason(
      context: context,
      fillRatio: fillRatio,
      magnification: magnification,
      isRecommended: isRecommended,
      apertureMm: apertureMm,
    );

    final score = total.clamp(0, 100).toDouble();
    final screenFillNote = ScreenFillScoring.visualFillNote(fillRatio);

    return VisualEquipmentRecommendation(
      equipment: telescope,
      eyepiece: includeEyepiece || isRecommended ? eyepiece : null,
      score: score,
      starCount: ObservationScoreService.recommendationStarCount(score.round()),
      reason: reason,
      isRecommended: isRecommended,
      screenFillPercent: ScreenFillScoring.fillPercent(fillRatio),
      screenFillNote: screenFillNote,
    );
  }

  double _sizeFitScore(
    double fillRatio,
    ObjectType type, {
    double? idealRatioOverride,
  }) {
    if (idealRatioOverride != null) {
      final distance = (fillRatio - idealRatioOverride).abs();
      return (100 - distance * 140).clamp(15, 100);
    }
    return ScreenFillScoring.score(fillRatio);
  }

  double _telescopeScore({
    required double apertureMm,
    required double? fRatio,
    required SurfaceBrightnessClass brightness,
  }) {
    var score = switch (apertureMm) {
      >= 200 => 95.0,
      >= 150 => 85.0,
      >= 120 => 75.0,
      >= 90 => 60.0,
      >= 70 => 45.0,
      _ => 30.0,
    };

    if (fRatio != null) {
      if (fRatio <= 6) {
        score += 10;
      } else if (fRatio <= 8) {
        score += 5;
      } else if (brightness.index >= SurfaceBrightnessClass.dim.index) {
        score -= 20;
      } else if (fRatio > 10) {
        score -= 10;
      }
    }

    return score.clamp(10, 100);
  }

  String _reason({
    required VisualTargetContext context,
    required double fillRatio,
    required double magnification,
    required bool isRecommended,
    required double apertureMm,
  }) {
    if (!isRecommended) {
      if (context.suitability.requiresWideField &&
          apertureMm < VisualObservationWeights.minApertureWideFieldMm) {
        return '필터 없이 관측 어려움';
      }
      if (context.suitability.noFilterPenalty < 1.0 &&
          VisualObservationWeights.isNoFilterPenalizedType(
            context.profile.objectType,
          )) {
        return '필터 없이 관측 어려움';
      }
      if (context.visualSurfaceBrightness.index >=
          SurfaceBrightnessClass.veryDim.index) {
        return '표면 밝기가 매우 낮습니다.';
      }
      if (context.visualSurfaceBrightness.index >=
          SurfaceBrightnessClass.dim.index) {
        return '현재 장비로는 안시가 어렵습니다.';
      }
      if (fillRatio > ScreenFillScoring.idealMaxRatio) {
        return '전체 감상 적합';
      }
      return '필터 없이 관측 어려움';
    }

    if (context.suitability.observationBasis ==
        VisualObservationBasis.centralOpenCluster) {
      return '중앙 산개성단 관측 추천';
    }

    if (context.visualSurfaceBrightness.index <=
        SurfaceBrightnessClass.bright.index) {
      return '표면 밝기 우수';
    }
    if (magnification > 80 || fillRatio > 0.5) {
      return '고배율 적합';
    }
    return '전체 감상 적합';
  }
}
