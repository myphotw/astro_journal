import '../../core/constants/angular_size_class.dart';
import '../../core/constants/object_type.dart';
import '../../core/constants/surface_brightness_class.dart';
import '../../data/models/catalog_object.dart';
import '../../data/models/equipment.dart';
import '../../data/models/equipment_recommendation.dart';
import '../../data/models/fov_box.dart';
import '../../data/models/object_imaging_profile.dart';
import '../../data/models/recommendation_result.dart';
import '../../data/models/representative_framing_size.dart';
import '../../features/home/viewmodel/home_view_model.dart';
import '../object_imaging_profile_provider.dart';
import '../observation_score_service.dart';
import 'field_orientation_calculator.dart';
import 'representative_framing_resolver.dart';
import 'screen_fill_scoring.dart';
import 'visual_observation_scorer.dart';
import 'visual_target_context.dart';
import '../celestial_position_service.dart';

/// 등록 장비 기준 촬영·안시 추천 (기존 RecommendationEngine과 독립).
class EquipmentRecommendationService {
  const EquipmentRecommendationService({
    ObjectImagingProfileProvider? profileProvider,
    RepresentativeFramingResolver? framingResolver,
    VisualObservationScorer? visualScorer,
  })  : _profileProvider =
            profileProvider ?? const ObjectImagingProfileProvider(),
        _framingResolver =
            framingResolver ?? const RepresentativeFramingResolver(),
        _visualScorer = visualScorer ?? const VisualObservationScorer();

  final ObjectImagingProfileProvider _profileProvider;
  final RepresentativeFramingResolver _framingResolver;
  final VisualObservationScorer _visualScorer;

  ObjectEquipmentRecommendation recommendForObject({
    required CatalogObject object,
    required List<Equipment> equipment,
    ImagingOrientationContext? orientation,
  }) {
    final active = equipment.where((e) => e.isActive).toList();
    if (active.isEmpty) {
      return ObjectEquipmentRecommendation.empty;
    }

    final framing = _framingResolver.resolve(object);
    final profile = _profileProvider.profileFor(object);

    final imaging = _rankImagingEquipment(
      active.where((e) => e.isImaging).toList(),
      framing: framing,
      profile: profile,
      orientation: orientation,
    );

    final visual = _rankVisualEquipment(
      active.where((e) => e.isVisual).toList(),
      object: object,
      framing: framing,
      profile: profile,
    );

    return ObjectEquipmentRecommendation(
      imaging: imaging,
      visual: visual,
      hasRegisteredEquipment: true,
    );
  }

  TodayEquipmentRecommendation recommendForToday({
    required CatalogObject object,
    required List<Equipment> equipment,
    required RecommendationResult recommendation,
    ObservationCondition? condition,
    double? targetAltitude,
    double? observerLatitude,
    double? observerLongitude,
  }) {
    final orientation = _orientationFromRecommendation(
      object: object,
      recommendation: recommendation,
      observerLatitude: observerLatitude,
      observerLongitude: observerLongitude,
    );

    final base = recommendForObject(
      object: object,
      equipment: equipment,
      orientation: orientation,
    );
    if (!base.hasRegisteredEquipment) {
      return TodayEquipmentRecommendation.empty;
    }

    final contextFactor = _todayContextFactor(
      recommendation: recommendation,
      condition: condition,
      targetAltitude: targetAltitude,
      profile: _profileProvider.profileFor(object),
    );

    ImagingEquipmentRecommendation? bestImaging;
    if (base.imaging.isNotEmpty) {
      final scored = base.imaging
          .map(
            (item) => (
              item: item,
              todayScore: (item.score * contextFactor.imagingMultiplier)
                  .clamp(0, 100),
            ),
          )
          .toList()
        ..sort((a, b) => b.todayScore.compareTo(a.todayScore));

      final top = scored.first;
      final todayScore = top.todayScore.toDouble();
      bestImaging = ImagingEquipmentRecommendation(
        equipment: top.item.equipment,
        score: todayScore,
        starCount: ObservationScoreService.recommendationStarCount(
          todayScore.round(),
        ),
        reason: _prioritizeEquipmentReason(
          equipmentReason: top.item.reason,
          conditionReason: contextFactor.imagingReason,
        ),
        screenFillPercent: top.item.screenFillPercent,
        screenFillNote: top.item.screenFillNote,
        rank: 1,
      );
    }

    List<VisualEquipmentRecommendation> todayVisual = const [];
    if (base.visual.isNotEmpty) {
      final blocked = base.visual.length == 1 && !base.visual.first.isRecommended;
      if (blocked) {
        final visual = base.visual.first;
        todayVisual = [
          VisualEquipmentRecommendation(
            equipment: visual.equipment,
            score: visual.score,
            starCount: visual.starCount,
            reason: contextFactor.visualBlockReason ?? visual.reason,
            isRecommended: false,
            screenFillPercent: visual.screenFillPercent,
            screenFillNote: visual.screenFillNote,
            isFeasibleToday: false,
          ),
        ];
      } else {
        todayVisual = base.visual
            .map((visual) {
              final todayScore = (visual.score * contextFactor.visualMultiplier)
                  .clamp(0, 100)
                  .toDouble();
              final feasible =
                  contextFactor.visualFeasible && visual.isRecommended;
              return VisualEquipmentRecommendation(
                equipment: visual.equipment,
                eyepiece: feasible ? visual.eyepiece : null,
                score: todayScore,
                starCount: ObservationScoreService.recommendationStarCount(
                  todayScore.round(),
                ),
                reason: feasible
                    ? _prioritizeEquipmentReason(
                        equipmentReason: visual.reason,
                        conditionReason: contextFactor.visualReason,
                      )
                    : (contextFactor.visualBlockReason ?? visual.reason),
                isRecommended: visual.isRecommended && feasible,
                screenFillPercent: visual.screenFillPercent,
                screenFillNote: visual.screenFillNote,
                isFeasibleToday: feasible,
              );
            })
            .where(
              (visual) => visual.isFeasibleToday && visual.eyepiece != null,
            )
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
      }
    }

    return TodayEquipmentRecommendation(
      imaging: bestImaging,
      visual: todayVisual,
      hasRegisteredEquipment: true,
    );
  }

  List<ImagingEquipmentRecommendation> _rankImagingEquipment(
    List<Equipment> imagingEquipment, {
    required RepresentativeFramingSize framing,
    required ObjectImagingProfile profile,
    ImagingOrientationContext? orientation,
  }) {
    final results = <ImagingEquipmentRecommendation>[];

    for (final equipment in imagingEquipment) {
      final fovW = equipment.fovWidthDegrees;
      final fovH = equipment.fovHeightDegrees;
      if (fovW == null || fovH == null || fovW <= 0 || fovH <= 0) continue;

      final framingResult = _imagingFraming(
        framing: framing,
        fieldOfViewWidthDegrees: fovW,
        fieldOfViewHeightDegrees: fovH,
        orientation: orientation,
      );
      final fillRatio = framingResult.bestCoverage;
      final score = _imagingScore(fillRatio, profile);
      final reason = _imagingReason(framingResult);

      results.add(
        ImagingEquipmentRecommendation(
          equipment: equipment,
          score: score,
          starCount: ObservationScoreService.recommendationStarCount(
            score.round(),
          ),
          reason: reason,
          screenFillPercent: framingResult.coveragePercent,
          screenFillNote: ScreenFillScoring.imagingFillNote(
            framingResult.recommendation,
          ),
        ),
      );
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return [
      for (var i = 0; i < results.length; i++)
        ImagingEquipmentRecommendation(
          equipment: results[i].equipment,
          score: results[i].score,
          starCount: results[i].starCount,
          reason: results[i].reason,
          screenFillPercent: results[i].screenFillPercent,
          screenFillNote: results[i].screenFillNote,
          rank: i + 1,
        ),
    ];
  }

  FramingCoverageResult _imagingFraming({
    required RepresentativeFramingSize framing,
    required double fieldOfViewWidthDegrees,
    required double fieldOfViewHeightDegrees,
    ImagingOrientationContext? orientation,
  }) {
    if (orientation != null) {
      return FieldOrientationCalculator.bestFramingDuringWindow(
        framing: framing,
        fieldOfViewWidthDegrees: fieldOfViewWidthDegrees,
        fieldOfViewHeightDegrees: fieldOfViewHeightDegrees,
        latitudeDeg: orientation.latitude,
        longitudeDeg: orientation.longitude,
        raHours: orientation.raHours,
        declinationDeg: orientation.declinationDeg,
        windowStart: orientation.windowStart,
        windowEnd: orientation.windowEnd,
      );
    }

    return FieldOrientationCalculator.bestFramingFreeRotation(
      framing: framing,
      fieldOfViewWidthDegrees: fieldOfViewWidthDegrees,
      fieldOfViewHeightDegrees: fieldOfViewHeightDegrees,
    );
  }

  ImagingOrientationContext? _orientationFromRecommendation({
    required CatalogObject object,
    required RecommendationResult recommendation,
    double? observerLatitude,
    double? observerLongitude,
  }) {
    if (observerLatitude == null || observerLongitude == null) return null;

    final window = recommendation.observationWindow;
    if (window == null) return null;

    final start = window.recommendStartTime ??
        window.optimalStartTime ??
        window.peakAltitudeTime;
    final end = window.observationEndTime ?? window.optimalEndTime;
    if (start == null || end == null || !end.isAfter(start)) return null;

    return ImagingOrientationContext(
      latitude: observerLatitude,
      longitude: observerLongitude,
      raHours: CelestialPositionService.parseRaHours(object.ra),
      declinationDeg: CelestialPositionService.parseDecDeg(object.dec),
      windowStart: start,
      windowEnd: end,
    );
  }

  double _imagingScore(double fillRatio, ObjectImagingProfile profile) {
    var score = ScreenFillScoring.score(fillRatio);

    if (profile.angularSizeClass == AngularSizeClass.veryLarge &&
        fillRatio > ScreenFillScoring.idealMaxRatio) {
      score = (score + 8).clamp(0, 100);
    }

    if (profile.objectType == ObjectType.milkyWay &&
        fillRatio < ScreenFillScoring.idealMinRatio) {
      score = (score - 15).clamp(0, 100);
    }

    return score;
  }

  String _imagingReason(FramingCoverageResult framing) {
    if (framing.bestCoverage < 0.05) {
      return '천체가 너무 작음';
    }
    return ScreenFillScoring.reasonFromRecommendation(framing.recommendation);
  }

  List<VisualEquipmentRecommendation> _rankVisualEquipment(
    List<Equipment> visualEquipment, {
    required CatalogObject object,
    required RepresentativeFramingSize framing,
    required ObjectImagingProfile profile,
  }) {
    if (visualEquipment.isEmpty) return const [];

    final context = VisualTargetContext.from(
      object: object,
      profile: profile,
      framingSize: framing,
    );

    return _visualScorer.rankRecommendations(
      context: context,
      visualEquipment: visualEquipment,
    );
  }

  _TodayContextFactor _todayContextFactor({
    required RecommendationResult recommendation,
    ObservationCondition? condition,
    double? targetAltitude,
    required ObjectImagingProfile profile,
  }) {
    if (condition == null) {
      return _TodayContextFactor(
        imagingMultiplier: recommendation.score / 100,
        visualMultiplier: recommendation.score / 100,
        visualFeasible: true,
        imagingReason: '현재 조건 최적',
      );
    }

    var imagingMult = (recommendation.score / 100).clamp(0.3, 1.0);
    var visualMult = imagingMult;
    var visualFeasible = condition.isObservationFeasible;
    String? imagingReason;
    String? visualReason;
    String? visualBlockReason;

    final altitude = targetAltitude ??
        recommendation.observationWindow?.currentAltitude ??
        recommendation.observationWindow?.peakAltitude;

    if (altitude != null && altitude < 25) {
      imagingMult *= 0.75;
      visualMult *= 0.7;
      imagingReason = '고도가 낮음';
      visualReason = '고도가 낮음';
    }

    if (condition.cloudCover > 50) {
      imagingMult *= 0.7;
      visualMult *= 0.5;
      visualFeasible = false;
      visualBlockReason = '현재 조건 부적합';
    }

    if (condition.moon.illumination > 0.6 &&
        profile.surfaceBrightnessClass.index >=
            SurfaceBrightnessClass.normal.index) {
      imagingMult *= 0.85;
      visualMult *= 0.6;
      if (profile.surfaceBrightnessClass.index >=
          SurfaceBrightnessClass.dim.index) {
        visualFeasible = false;
        visualBlockReason = '달 영향 큼';
      } else {
        visualReason = '달 영향 큼';
      }
    }

    if (recommendation.moonSeparation < 45 &&
        profile.objectType != ObjectType.planet &&
        profile.objectType != ObjectType.moon) {
      visualMult *= 0.75;
    }

    if (condition.score >= 75 && imagingReason == null) {
      imagingReason = '현재 조건 최적';
    }

    if (!visualFeasible && visualBlockReason == null) {
      visualBlockReason = '현재 조건 부적합';
    }

    if (imagingMult > visualMult + 0.15 &&
        profile.surfaceBrightnessClass.index <=
            SurfaceBrightnessClass.normal.index) {
      visualReason ??= '오늘은 촬영 권장';
    }

    return _TodayContextFactor(
      imagingMultiplier: imagingMult,
      visualMultiplier: visualMult,
      visualFeasible: visualFeasible,
      imagingReason: imagingReason,
      visualReason: visualReason,
      visualBlockReason: visualBlockReason,
    );
  }

  /// 오늘 추천에서 장비 적합도 사유를 관측 조건 사유보다 우선한다.
  String _prioritizeEquipmentReason({
    required String equipmentReason,
    String? conditionReason,
  }) {
    if (equipmentReason.isNotEmpty) return equipmentReason;
    return conditionReason ?? '';
  }
}

class _TodayContextFactor {
  const _TodayContextFactor({
    required this.imagingMultiplier,
    required this.visualMultiplier,
    required this.visualFeasible,
    this.imagingReason,
    this.visualReason,
    this.visualBlockReason,
  });

  final double imagingMultiplier;
  final double visualMultiplier;
  final bool visualFeasible;
  final String? imagingReason;
  final String? visualReason;
  final String? visualBlockReason;
}

/// 오늘 밤 관측 창 기준 시야 회전을 반영한 촬영 프레이밍 계산용.
class ImagingOrientationContext {
  const ImagingOrientationContext({
    required this.latitude,
    required this.longitude,
    required this.raHours,
    required this.declinationDeg,
    required this.windowStart,
    required this.windowEnd,
  });

  final double latitude;
  final double longitude;
  final double raHours;
  final double declinationDeg;
  final DateTime windowStart;
  final DateTime windowEnd;
}
