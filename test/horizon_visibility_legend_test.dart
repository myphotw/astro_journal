import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/features/observation_site/widgets/horizon_visibility_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'uses one accessible legend for visible blocked and altitude states',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HorizonVisibilityOverview(
              points: const [
                HorizonPoint(
                  id: 'point',
                  observationSiteId: 'site',
                  azimuth: 90,
                  minAltitude: 25,
                ),
              ],
              blockedRanges: const [
                BlockedAzimuthRange(
                  id: 'blocked',
                  observationSiteId: 'site',
                  startAzimuth: 180,
                  endAzimuth: 220,
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('horizon-visibility-legend')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('horizon-legend-visible')), findsOneWidget);
      expect(find.byKey(const Key('horizon-legend-blocked')), findsOneWidget);
      expect(find.byKey(const Key('horizon-legend-altitude')), findsOneWidget);
      expect(find.text('촬영 가능 시야'), findsOneWidget);
      expect(find.text('장애물 / 촬영 불가 영역'), findsOneWidget);
      expect(find.text('최소 가시 고도'), findsOneWidget);
    },
  );
}
