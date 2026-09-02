import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/features/home/view/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ImagingSuitabilityAssessment assessment({
    required FilterMode filterMode,
    required MosaicMode mosaicMode,
  }) {
    return ImagingSuitabilityAssessment(
      quality: ExpectedResultQuality.mainStructure,
      filterMode: filterMode,
      mosaicMode: mosaicMode,
      trackingMode: TrackingMode.altAz,
      suitabilityScore: 75,
      scoreMultiplier: 1,
      reason: 'test',
      hasReliableSurfaceBrightness: true,
    );
  }

  testWidgets('recommendation card status shows Filter ON and Mosaic chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecommendationImagingStatusChips(
          assessment: assessment(
            filterMode: FilterMode.on,
            mosaicMode: MosaicMode.on,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('recommendation-filter-on')), findsOneWidget);
    expect(find.text('필터 ON'), findsOneWidget);
    expect(find.byKey(const Key('recommendation-mosaic-on')), findsOneWidget);
    expect(find.text('모자이크'), findsOneWidget);
    expect(find.byKey(const Key('recommendation-quality')), findsOneWidget);
  });

  testWidgets('Filter OFF remains visible and Mosaic OFF is omitted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecommendationImagingStatusChips(
          assessment: assessment(
            filterMode: FilterMode.off,
            mosaicMode: MosaicMode.off,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('recommendation-filter-off')), findsOneWidget);
    expect(find.text('필터 OFF'), findsOneWidget);
    expect(find.byKey(const Key('recommendation-mosaic-on')), findsNothing);
    expect(find.byKey(const Key('recommendation-quality')), findsOneWidget);
  });
}
