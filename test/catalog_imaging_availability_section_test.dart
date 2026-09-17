import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/recommendation_result.dart';
import 'package:astro_journal/data/models/shooting_time_window.dart';
import 'package:astro_journal/data/models/target_imaging_availability.dart';
import 'package:astro_journal/shared/widgets/catalog_imaging_availability_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final object = CatalogObject(
    id: 'm31',
    number: 31,
    catalog: CatalogType.messier,
    name: 'M31',
    type: '은하',
    constellation: 'And',
    ra: '00h 42m',
    dec: '+41° 16m',
    magnitude: '3.4',
  );
  final sites = [
    ObservationSite(
      id: 'home',
      name: '집',
      latitude: 37.5,
      longitude: 127,
      bortle: 8,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    ObservationSite(
      id: 'guree',
      name: '구례',
      latitude: 35.2,
      longitude: 127.4,
      bortle: 4,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];

  testWidgets(
    'shows selected site and unavailable reason without changing site data',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogImagingAvailabilitySection(
              sites: sites,
              selectedSite: sites.first,
              availability: TargetImagingAvailability(
                object: object,
                referenceDate: DateTime(2026, 9, 3),
                isAvailableTonight: false,
                primaryReason: '관측 가능 시간 동안 고도가 부족합니다.',
                tomorrow: TargetImagingAvailability(
                  object: object,
                  referenceDate: DateTime(2026, 9, 4),
                  isAvailableTonight: true,
                ),
                observableSeasonLabel: '9월 ~ 2월',
                optimalSeasonLabel: '11월 ~ 1월',
              ),
              isLoading: false,
              onSelectSite: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('등록 관측지 촬영 가능성'), findsOneWidget);
      expect(find.text('등록 관측지'), findsOneWidget);
      expect(find.text('촬영 가능성'), findsNothing);
      expect(find.text('집 (Bortle 8)'), findsOneWidget);
      expect(find.text('관측 가능 구간 없음'), findsOneWidget);
      expect(find.text('관측 가능 시간 동안 고도가 부족합니다.'), findsOneWidget);
      expect(find.text('오늘 9/3'), findsOneWidget);
      expect(find.text('내일 9/4'), findsOneWidget);
      expect(find.text('· 기상정보 미반영'), findsOneWidget);
      expect(
        find.byKey(const Key('catalog-availability-days-row')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('availability-today-card')), findsOneWidget);
      expect(
        find.byKey(const Key('availability-tomorrow-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('availability-today-season')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('availability-tomorrow-season')),
        findsOneWidget,
      );
      final tomorrowTop = tester.getTopLeft(find.text('내일 9/4')).dy;
      final weatherTop = tester.getTopLeft(find.text('· 기상정보 미반영')).dy;
      expect((tomorrowTop - weatherTop).abs(), lessThanOrEqualTo(2));
      expect(find.text('9월 ~ 2월'), findsNWidgets(2));
      for (final row in const [
        'status',
        'shooting-window',
        'optimal-window',
        'season',
      ]) {
        final todayTop = tester
            .getTopLeft(find.byKey(Key('availability-today-$row')))
            .dy;
        final tomorrowRowTop = tester
            .getTopLeft(find.byKey(Key('availability-tomorrow-$row')))
            .dy;
        expect((todayTop - tomorrowRowTop).abs(), lessThanOrEqualTo(1));
      }
    },
  );

  testWidgets('uses a vertical day layout on a narrow screen', (tester) async {
    final value = TargetImagingAvailability(
      object: object,
      referenceDate: DateTime(2026, 9, 3),
      isAvailableTonight: true,
      tomorrow: TargetImagingAvailability(
        object: object,
        referenceDate: DateTime(2026, 9, 4),
        isAvailableTonight: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: CatalogImagingAvailabilitySection(
                sites: sites,
                selectedSite: sites.first,
                availability: value,
                isLoading: false,
                onSelectSite: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('catalog-availability-days-column')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('catalog-availability-days-row')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an empty registered-site state independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogImagingAvailabilitySection(
            sites: const [],
            selectedSite: null,
            availability: null,
            isLoading: false,
            onSelectSite: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('등록 관측지 촬영 가능성'), findsOneWidget);
    expect(find.text('등록된 관측지가 없습니다.'), findsOneWidget);
  });

  testWidgets('bad weather remains advice beside astronomical windows', (
    tester,
  ) async {
    final start = DateTime(2026, 9, 3, 21, 10);
    final optimalStart = DateTime(2026, 9, 4, 0, 15);
    final optimalEnd = DateTime(2026, 9, 4, 1, 35);
    final end = DateTime(2026, 9, 4, 4, 20);
    final usableWindow = ShootingTimeWindow(
      start: DateTime(2026, 9, 4, 3, 10),
      end: DateTime(2026, 9, 4, 4),
    );
    final recommendation = RecommendationResult(
      object: object,
      reasons: const [],
      season: '가을',
      score: 35,
      moonSeparation: 90,
      observationWindow: ObjectObservationWindow(
        currentAltitude: 35,
        currentAzimuth: 180,
        isCurrentlyVisible: true,
        recommendStartTime: start,
        optimalStartTime: optimalStart,
        optimalEndTime: optimalEnd,
        observationEndTime: end,
        totalObservableMinutes: end.difference(start).inMinutes,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogImagingAvailabilitySection(
            sites: sites,
            selectedSite: sites.first,
            availability: TargetImagingAvailability(
              object: object,
              referenceDate: DateTime(2026, 9, 3),
              isAvailableTonight: true,
              recommendation: recommendation,
              state: TargetImagingAvailabilityState.sufficientWindow,
              usableWindow: usableWindow,
              usableMinutes: 50,
              minimumMinutes: 30,
              recommendedMinutes: 60,
              weatherAdvisory:
                  '구름량 100% 예보가 있습니다. 실제 하늘 상태를 확인해 주세요.',
            ),
            isLoading: false,
            onSelectSite: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('21:10 ~ 04:20'), findsOneWidget);
    expect(find.text('03:10 ~ 04:00 · 50분'), findsOneWidget);
    expect(usableWindow.duration.inMinutes, 50);
    expect(find.text('천문학적 관측 가능'), findsOneWidget);
    expect(find.text('실제 촬영 가능'), findsOneWidget);
    expect(find.text('00:15 ~ 01:35'), findsOneWidget);
    expect(find.text('기상 의견'), findsOneWidget);
    expect(find.textContaining('실제 하늘 상태를 확인해 주세요.'), findsOneWidget);
    expect(find.text('촬영 불가'), findsNothing);
    expect(find.text('관측 불가'), findsNothing);
  });

  for (final scenario in <({
    TargetImagingAvailabilityState state,
    String label,
    int? usableMinutes,
    bool hasReference,
    bool framingMatched,
  })>[
    (
      state: TargetImagingAvailabilityState.noObservableWindow,
      label: '관측 가능 구간 없음',
      usableMinutes: null,
      hasReference: false,
      framingMatched: false,
    ),
    (
      state: TargetImagingAvailabilityState.shortWindow,
      label: '촬영 가능 시간이 짧음',
      usableMinutes: 17,
      hasReference: false,
      framingMatched: false,
    ),
    (
      state: TargetImagingAvailabilityState.multiNightAccumulation,
      label: '동일구도 누적 가능',
      usableMinutes: 17,
      hasReference: true,
      framingMatched: true,
    ),
    (
      state: TargetImagingAvailabilityState.sufficientWindow,
      label: '최소 촬영시간 충족',
      usableMinutes: 60,
      hasReference: false,
      framingMatched: false,
    ),
  ]) {
    testWidgets('renders semantic availability state: ${scenario.label}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogImagingAvailabilitySection(
              sites: sites,
              selectedSite: sites.first,
              availability: TargetImagingAvailability(
                object: object,
                referenceDate: DateTime(2026, 9, 3),
                isAvailableTonight:
                    scenario.state !=
                    TargetImagingAvailabilityState.noObservableWindow,
                state: scenario.state,
                usableMinutes: scenario.usableMinutes,
                minimumMinutes: 30,
                recommendedMinutes: 60,
                hasFramingReference: scenario.hasReference,
                framingMatched: scenario.framingMatched,
                sameFramingMinutes: scenario.framingMatched ? 17 : null,
              ),
              isLoading: false,
              onSelectSite: (_) {},
            ),
          ),
        ),
      );

      Finder textInTodayRow(String row, String text) => find.descendant(
        of: find.byKey(Key('availability-today-$row')),
        matching: find.text(text),
      );

      expect(textInTodayRow('status', scenario.label), findsOneWidget);
      expect(find.text('촬영 불가'), findsNothing);
      expect(
        textInTodayRow('minimum-duration', '일반 최소 기준'),
        findsOneWidget,
      );
      expect(textInTodayRow('minimum-duration', '30분'), findsOneWidget);
      expect(
        textInTodayRow('recommended-duration', '권장 촬영시간'),
        findsOneWidget,
      );
      expect(textInTodayRow('recommended-duration', '60분'), findsOneWidget);
      if (scenario.usableMinutes != null) {
        expect(
          textInTodayRow('usable-duration', '실제 촬영 가능'),
          findsOneWidget,
        );
        expect(
          textInTodayRow('usable-duration', '${scenario.usableMinutes}분'),
          findsOneWidget,
        );
      } else {
        expect(
          find.byKey(const Key('availability-today-usable-duration')),
          findsNothing,
        );
      }
      if (scenario.framingMatched) {
        expect(
          textInTodayRow('framing-status', '동일구도 17분 누적 가능'),
          findsOneWidget,
        );
      }
    });
  }

  for (final scenario in <({bool today, bool tomorrow, String name})>[
    (today: true, tomorrow: true, name: 'today and tomorrow available'),
    (
      today: false,
      tomorrow: true,
      name: 'today unavailable tomorrow available',
    ),
    (
      today: true,
      tomorrow: false,
      name: 'today available tomorrow unavailable',
    ),
    (today: false, tomorrow: false, name: 'today and tomorrow unavailable'),
  ]) {
    testWidgets(scenario.name, (tester) async {
      final tomorrow = TargetImagingAvailability(
        object: object,
        referenceDate: DateTime(2026, 9, 4),
        isAvailableTonight: scenario.tomorrow,
        primaryReason: scenario.tomorrow ? null : '고도 부족',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogImagingAvailabilitySection(
              sites: sites,
              selectedSite: sites.first,
              availability: TargetImagingAvailability(
                object: object,
                referenceDate: DateTime(2026, 9, 3),
                isAvailableTonight: scenario.today,
                primaryReason: scenario.today ? null : '구름 많음',
                tomorrow: tomorrow,
                observableSeasonLabel: '8월 ~ 2월',
                optimalSeasonLabel: '10월 ~ 12월',
              ),
              isLoading: false,
              onSelectSite: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('오늘 9/3'), findsOneWidget);
      expect(find.text('내일 9/4'), findsOneWidget);
      expect(find.text('· 기상정보 미반영'), findsOneWidget);
      expect(find.text('8월 ~ 2월'), findsNWidgets(2));
      expect(find.text('10월 ~ 12월'), findsNWidgets(2));
      if (!scenario.tomorrow) {
        expect(find.text('고도 부족'), findsOneWidget);
      }
    });
  }
}
