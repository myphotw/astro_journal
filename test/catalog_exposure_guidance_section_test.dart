import 'package:astro_journal/data/models/catalog_exposure_guidance.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/shared/widgets/catalog_exposure_guidance_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('catalog guide renders shared Filter and Mosaic modes', (
    tester,
  ) async {
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
      const MaterialApp(
        home: Scaffold(
          body: CatalogExposureGuidanceSection(guidance: guidance),
        ),
      ),
    );

    expect(find.text('필터'), findsOneWidget);
    expect(find.text('OFF'), findsOneWidget);
    expect(find.text('모자이크'), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);
  });
}
