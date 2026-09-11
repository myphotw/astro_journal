import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/catalog_exposure_guidance.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/recommendation_result.dart';
import 'package:astro_journal/data/models/target_imaging_availability.dart';
import 'package:astro_journal/shared/widgets/catalog_exposure_guidance_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('catalog guide renders shared Filter and Mosaic modes', (
    tester,
  ) async {
    const object = CatalogObject(
      id: 'M16',
      number: 16,
      catalog: CatalogType.messier,
      name: '독수리성운',
      type: '성운',
      constellation: '뱀자리',
      ra: '18h 18.8m',
      dec: '-13° 47m',
      magnitude: '6.0',
    );
    const guidance = CatalogExposureGuidance(
      referenceBortle: 5,
      feasibility: CatalogExposureFeasibility.recommended,
      currentMinimumMinutes: 30,
      currentRecommendedMinutes: 60,
      imagingAssessment: ImagingSuitabilityAssessment(
        quality: ExpectedResultQuality.mainStructure,
        filterMode: FilterMode.off,
        mosaicMode: MosaicMode.on,
        trackingMode: TrackingMode.eq,
        suitabilityScore: 70,
        scoreMultiplier: 0.8,
        reason: '단일 화각보다 큰 대상 — 모자이크 촬영을 권장합니다.',
        hasReliableSurfaceBrightness: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogExposureGuidanceSection(
            guidance: guidance,
            availability: TargetImagingAvailability(
              object: object,
              referenceDate: DateTime(2026, 8, 4),
              isAvailableTonight: true,
              recommendation: RecommendationResult(
                object: object,
                reasons: const [],
                season: '여름',
                score: 80,
                moonSeparation: 90,
                observationWindow: ObjectObservationWindow(
                  currentAltitude: 30,
                  currentAzimuth: 180,
                  isCurrentlyVisible: true,
                  recommendStartTime: DateTime(2026, 8, 4, 20),
                  optimalStartTime: DateTime(2026, 8, 4, 20, 10),
                  optimalEndTime: DateTime(2026, 8, 4, 21, 20),
                  observationEndTime: DateTime(2026, 8, 4, 21, 30),
                ),
              ),
            ),
            site: ObservationSite(
              id: 'home',
              name: '집',
              latitude: 37.5,
              longitude: 127,
              bortle: 9,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          ),
        ),
      ),
    );

    expect(find.text('현재 관측지'), findsOneWidget);
    expect(find.text('집 · Bortle 9'), findsOneWidget);
    expect(find.text('권장 촬영시간'), findsOneWidget);
    expect(find.text('60분'), findsOneWidget);
    final todaySummary = find.byKey(const Key('catalog-today-status'));
    expect(todaySummary, findsOneWidget);
    expect(
      find.descendant(of: todaySummary, matching: find.text('오늘')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: todaySummary, matching: find.text('촬영 가능')),
      findsOneWidget,
    );
    final availableWindowSummary = find.byKey(
      const Key('catalog-available-window'),
    );
    expect(availableWindowSummary, findsOneWidget);
    expect(
      find.descendant(of: availableWindowSummary, matching: find.text('촬영 가능')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: availableWindowSummary,
        matching: find.text('20:00 ~ 21:30'),
      ),
      findsOneWidget,
    );
    final summaryKeys = [
      const Key('catalog-today-status'),
      const Key('catalog-available-window'),
      const Key('catalog-optimal-window'),
      const Key('catalog-recommended-duration'),
    ];
    final firstTop = tester.getTopLeft(find.byKey(summaryKeys.first)).dy;
    for (final key in summaryKeys.skip(1)) {
      expect(
        (tester.getTopLeft(find.byKey(key)).dy - firstTop).abs(),
        lessThanOrEqualTo(1),
      );
    }
    expect(
      tester.widget<Text>(find.text('60분')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(find.text('20:00 ~ 21:30'), findsOneWidget);
    expect(find.text('20:10 ~ 21:20'), findsOneWidget);
    expect(find.textContaining('현재 환경'), findsNothing);
    expect(find.text('필터'), findsOneWidget);
    expect(find.text('OFF'), findsOneWidget);
    expect(find.text('모자이크'), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);

    final section = tester.widget<CatalogExposureGuidanceSection>(
      find.byType(CatalogExposureGuidanceSection),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: CatalogExposureGuidanceSection(
                guidance: section.guidance,
                site: section.site,
                availability: section.availability,
                isAvailabilityLoading: section.isAvailabilityLoading,
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('catalog-available-window'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const Key('catalog-today-status'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
