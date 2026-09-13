import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/features/observation_site/widgets/horizon_visibility_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const limitedPoints = [
    HorizonPoint(
      id: 'p120',
      observationSiteId: 'site',
      azimuth: 120,
      minAltitude: 20,
      maxAltitude: 65,
    ),
    HorizonPoint(
      id: 'p180',
      observationSiteId: 'site',
      azimuth: 180,
      minAltitude: 50,
      maxAltitude: 65,
    ),
    HorizonPoint(
      id: 'p220',
      observationSiteId: 'site',
      azimuth: 220,
      minAltitude: 20,
      maxAltitude: 65,
    ),
  ];
  const limitedBlocked = [
    BlockedAzimuthRange(
      id: 'blocked',
      observationSiteId: 'site',
      startAzimuth: 216,
      endAzimuth: 119,
    ),
  ];

  testWidgets('shows the two-dimensional profile and simplified legend', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HorizonVisibilityOverview(
            points: limitedPoints,
            blockedRanges: limitedBlocked,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('horizon-visibility-profile')), findsOneWidget);
    expect(
      find.byKey(const Key('observation-site-horizon-visualization')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('horizon-visibility-legend')), findsOneWidget);
    expect(find.text('보이는 하늘 영역'), findsOneWidget);
    expect(find.text('가려진 영역'), findsOneWidget);
    expect(find.text('최소 가시 고도'), findsNothing);
    expect(find.text('북 0°'), findsOneWidget);
    expect(find.text('동 90°'), findsOneWidget);
    expect(find.text('남 180°'), findsOneWidget);
    expect(find.text('서 270°'), findsOneWidget);
    expect(find.text('북 360°'), findsOneWidget);
    expect(find.text('90°'), findsOneWidget);
    expect(find.text('60°'), findsOneWidget);
    expect(find.text('30°'), findsOneWidget);
    expect(find.text('0°'), findsOneWidget);
  });

  testWidgets('passes limited min max and blocked data to the painter', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HorizonVisibilityOverview(
            points: limitedPoints,
            blockedRanges: limitedBlocked,
          ),
        ),
      ),
    );

    final paint = tester.widget<CustomPaint>(
      find.byKey(const Key('observation-site-horizon-visualization')),
    );
    final painter = paint.painter! as HorizonVisibilityProfilePainter;
    expect(painter.data.isBlocked(80), isTrue);
    expect(painter.data.isBlocked(150), isFalse);
    expect(painter.data.minAltitudeAt(120), 20);
    expect(painter.data.minAltitudeAt(180), 50);
    expect(painter.data.maxAltitudeAt(150), 65);
  });

  testWidgets('profile fits a narrow mobile surface without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HorizonVisibilityOverview(
            points: limitedPoints,
            blockedRanges: limitedBlocked,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('horizon-visibility-profile')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('full-sky data connects north and treats legacy null max as 90', () {
    final data = HorizonVisibilityProfileData(
      points: const [
        HorizonPoint(
          id: 'p350',
          observationSiteId: 'site',
          azimuth: 350,
          minAltitude: 10,
        ),
        HorizonPoint(
          id: 'p20',
          observationSiteId: 'site',
          azimuth: 20,
          minAltitude: 12,
        ),
      ],
      blockedRanges: const [],
    );

    expect(data.isBlocked(0), isFalse);
    expect(data.minAltitudeAt(0), closeTo(10.67, 0.01));
    expect(data.minAltitudeAt(360), closeTo(10.67, 0.01));
    expect(data.maxAltitudeAt(0), 90);
    expect(data.maxAltitudeAt(180), 90);
  });
}
