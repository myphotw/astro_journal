import 'dart:ui';

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

  testWidgets('editable profile handles touch and mouse boundary dragging', (
    tester,
  ) async {
    var points = <HorizonPoint>[
      const HorizonPoint(
        id: 'editable',
        observationSiteId: 'site',
        azimuth: 180,
        minAltitude: 20,
        maxAltitude: 60,
      ),
    ];
    HorizonGraphSelection? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setState) {
                return HorizonVisibilityOverview(
                  points: points,
                  blockedRanges: const [],
                  editable: true,
                  selection: selection,
                  onSelectionChanged: (value) {
                    setState(() => selection = value);
                  },
                  onAltitudeChanged: (selected, altitude) {
                    setState(() {
                      selection = selected;
                      final point = points.single;
                      points = [
                        selected.boundary == HorizonBoundaryKind.minimum
                            ? point.copyWith(minAltitude: altitude)
                            : point.copyWith(maxAltitude: altitude),
                      ];
                    });
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    final graph = find.byKey(const Key('editable-horizon-graph'));
    final rect = tester.getRect(graph);
    Offset at(double azimuth, double altitude) => Offset(
      rect.left + rect.width * azimuth / 360,
      rect.top + rect.height * (1 - altitude / 90),
    );

    await tester.tapAt(at(180, 20));
    await tester.pump();
    expect(selection?.pointId, 'editable');
    expect(selection?.boundary, HorizonBoundaryKind.minimum);

    await tester.dragFrom(at(180, 20), const Offset(0, -40));
    await tester.pump();
    expect(points.single.minAltitude, greaterThan(20));
    expect(
      points.single.minAltitude,
      points.single.minAltitude.roundToDouble(),
    );

    await tester.tapAt(at(180, 60));
    await tester.pump();
    expect(selection?.boundary, HorizonBoundaryKind.maximum);
    await tester.dragFrom(
      at(180, 60),
      at(180, 40) - at(180, 60),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(selection?.boundary, HorizonBoundaryKind.maximum);
    expect(points.single.maxAltitude, closeTo(40, 1));
  });

  testWidgets(
    'blocked range handles take priority and drag in one-degree azimuth steps',
    (tester) async {
      final points = <HorizonPoint>[
        const HorizonPoint(
          id: 'same-position',
          observationSiteId: 'site',
          azimuth: 89,
          minAltitude: 0,
        ),
      ];
      var ranges = <BlockedAzimuthRange>[
        const BlockedAzimuthRange(
          id: 'wrap',
          observationSiteId: 'site',
          startAzimuth: 224,
          endAzimuth: 89,
          reason: '동쪽 건물',
        ),
      ];
      HorizonBlockedRangeSelection? blockedSelection;
      var altitudeChanges = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: StatefulBuilder(
                builder: (context, setState) => HorizonVisibilityOverview(
                  points: points,
                  blockedRanges: ranges,
                  editable: true,
                  blockedSelection: blockedSelection,
                  onAltitudeChanged: (_, _) => altitudeChanges++,
                  onBlockedSelectionChanged: (value) {
                    setState(() => blockedSelection = value);
                  },
                  onBlockedAzimuthChanged: (selection, azimuth) {
                    setState(() {
                      blockedSelection = selection;
                      final range = ranges.single;
                      ranges = [
                        BlockedAzimuthRange(
                          id: range.id,
                          observationSiteId: range.observationSiteId,
                          startAzimuth: range.startAzimuth,
                          endAzimuth: azimuth,
                          reason: range.reason,
                          source: range.source,
                        ),
                      ];
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final graph = find.byKey(const Key('editable-horizon-graph'));
      final rect = tester.getRect(graph);
      Offset handle(double azimuth) =>
          Offset(rect.left + rect.width * azimuth / 360, rect.bottom - 12);

      await tester.dragFrom(handle(89), Offset(rect.width * 15 / 360, 0));
      await tester.pump();

      expect(blockedSelection?.rangeId, 'wrap');
      expect(blockedSelection?.boundary, BlockedRangeBoundaryKind.end);
      expect(ranges.single.startAzimuth, 224);
      expect(ranges.single.endAzimuth, 104);
      expect(ranges.single.reason, '동쪽 건물');
      expect(points.single.azimuth, 89);
      expect(points.single.minAltitude, 0);
      expect(altitudeChanges, 0);

      final paint = tester.widget<CustomPaint>(
        find.byKey(const Key('observation-site-horizon-visualization')),
      );
      final painter = paint.painter! as HorizonVisibilityProfilePainter;
      expect(painter.data.isBlocked(104), isTrue);
      expect(painter.data.isBlocked(105), isFalse);
    },
  );

  testWidgets('blocked start handle crosses 360 degrees with mouse input', (
    tester,
  ) async {
    var range = const BlockedAzimuthRange(
      id: 'north-wrap',
      observationSiteId: 'site',
      startAzimuth: 350,
      endAzimuth: 20,
    );
    HorizonBlockedRangeSelection? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setState) => HorizonVisibilityOverview(
                points: const [],
                blockedRanges: [range],
                editable: true,
                blockedSelection: selection,
                onBlockedSelectionChanged: (value) {
                  setState(() => selection = value);
                },
                onBlockedAzimuthChanged: (value, azimuth) {
                  setState(() {
                    selection = value;
                    range = BlockedAzimuthRange(
                      id: range.id,
                      observationSiteId: range.observationSiteId,
                      startAzimuth: azimuth,
                      endAzimuth: range.endAzimuth,
                    );
                  });
                },
              ),
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(
      find.byKey(const Key('editable-horizon-graph')),
    );
    final start = Offset(rect.left + rect.width * 350 / 360, rect.bottom - 12);
    await tester.dragFrom(
      start,
      Offset(rect.width * 10 / 360, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(selection?.boundary, BlockedRangeBoundaryKind.start);
    expect(range.startAzimuth, 0);
    expect(range.endAzimuth, 20);
  });

  testWidgets(
    'empty graph position produces an addable interpolated candidate',
    (tester) async {
      HorizonGraphSelection? selection;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: HorizonVisibilityOverview(
                points: limitedPoints,
                blockedRanges: limitedBlocked,
                editable: true,
                onSelectionChanged: (value) => selection = value,
              ),
            ),
          ),
        ),
      );

      final rect = tester.getRect(
        find.byKey(const Key('editable-horizon-graph')),
      );
      await tester.tapAt(
        Offset(rect.left + rect.width * 40 / 360, rect.top + rect.height / 2),
      );
      await tester.pump();

      expect(selection?.pointId, isNull);
      expect(selection?.azimuth, closeTo(40, 1));
    },
  );

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
