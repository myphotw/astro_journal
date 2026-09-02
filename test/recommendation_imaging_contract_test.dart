import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/recommendation_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RecommendationResult copyWith preserves imaging contract values', () {
    const assessment = ImagingSuitabilityAssessment(
      quality: ExpectedResultQuality.mainStructure,
      filterMode: FilterMode.on,
      mosaicMode: MosaicMode.on,
      trackingMode: TrackingMode.altAz,
      suitabilityScore: 72,
      imagingEfficiencyScore: 74,
      scoreMultiplier: 0.9,
      reason: 'test',
      hasReliableSurfaceBrightness: true,
      recommendedDailyExposure: Duration(minutes: 60),
      preferredHaWindow: TargetPreferredHaWindow(
        startHours: -1,
        endHours: 0,
        centerHours: -0.5,
        durationMinutes: 60,
      ),
      dailyDurationLimitedByFieldRotation: true,
    );
    const result = RecommendationResult(
      object: CatalogObject(
        id: 'm42',
        number: 42,
        catalog: CatalogType.messier,
        name: 'M42',
        type: '발광성운',
        constellation: 'Orion',
        ra: '5h 35m',
        dec: '-05° 23m',
        magnitude: '4.0',
      ),
      reasons: [],
      season: '겨울',
      score: 80,
      moonSeparation: 90,
      observationWindow: ObjectObservationWindow(
        currentAltitude: 45,
        currentAzimuth: 180,
        isCurrentlyVisible: true,
      ),
      imagingAssessment: assessment,
      minimumExposure: Duration(minutes: 30),
      recommendedExposure: Duration(minutes: 180),
      observingConditionScore: 83,
    );

    final copied = result.copyWith(score: 81);

    expect(copied.imagingAssessment, same(assessment));
    expect(copied.observingConditionScore, 83);
    expect(copied.recommendedTotalIntegration, const Duration(minutes: 180));
    expect(copied.recommendedDailyIntegration, const Duration(minutes: 60));
    expect(copied.imagingAssessment!.imagingEfficiencyScore, 74);
  });
}
