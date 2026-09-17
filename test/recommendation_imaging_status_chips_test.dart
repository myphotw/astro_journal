import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/features/home/view/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ImagingSuitabilityAssessment assessment({
    required FilterMode filterMode,
    required MosaicMode mosaicMode,
    ExpectedResultQuality quality = ExpectedResultQuality.mainStructure,
  }) {
    return ImagingSuitabilityAssessment(
      quality: quality,
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
    expect(find.text('예상 촬영 결과'), findsOneWidget);
    expect(find.text('★★★☆☆'), findsOneWidget);
    expect(find.text('· 주요 구조 확인'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('recommendation-quality')),
        matching: find.byType(Container),
      ),
      findsNothing,
    );
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

  for (final quality in [
    ExpectedResultQuality.detail,
    ExpectedResultQuality.excellent,
  ]) {
    testWidgets(
      '${quality.name} quality remains separated at narrow width and large text scale',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.4),
                  ),
                  child: SizedBox(
                    width: 120,
                    child: RecommendationImagingStatusChips(
                      assessment: assessment(
                        filterMode: FilterMode.on,
                        mosaicMode: MosaicMode.off,
                        quality: quality,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final label = find.text('예상 촬영 결과');
        final stars = find.text(quality.starLabel);
        final description = find.text('· ${quality.label}');
        expect(label, findsOneWidget);
        expect(stars, findsOneWidget);
        expect(description, findsOneWidget);
        expect(tester.getRect(label).overlaps(tester.getRect(stars)), isFalse);
        expect(
          tester.getRect(stars).overlaps(tester.getRect(description)),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
