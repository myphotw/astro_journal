import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/observation_site.dart';
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
      id: 'home', name: '집', latitude: 37.5, longitude: 127, bortle: 8,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    ),
    ObservationSite(
      id: 'guree', name: '구례', latitude: 35.2, longitude: 127.4, bortle: 4,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    ),
  ];

  testWidgets('shows selected site and unavailable reason without changing site data', (tester) async {
    await tester.pumpWidget(MaterialApp(
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
    ));

    expect(find.text('집 (Bortle 8)'), findsOneWidget);
    expect(find.text('촬영 불가'), findsOneWidget);
    expect(find.text('관측 가능 시간 동안 고도가 부족합니다.'), findsOneWidget);
    expect(find.text('오늘 9/3'), findsOneWidget);
    expect(find.text('내일 9/4'), findsOneWidget);
    expect(find.text('· 기상정보 미반영'), findsOneWidget);
    final tomorrowTop = tester.getTopLeft(find.text('내일 9/4')).dy;
    final weatherTop = tester.getTopLeft(find.text('· 기상정보 미반영')).dy;
    expect((tomorrowTop - weatherTop).abs(), lessThanOrEqualTo(2));
    expect(find.text('9월 ~ 2월'), findsOneWidget);
  });

  for (final scenario in <({bool today, bool tomorrow, String name})>[
    (today: true, tomorrow: true, name: 'today and tomorrow available'),
    (today: false, tomorrow: true, name: 'today unavailable tomorrow available'),
    (today: true, tomorrow: false, name: 'today available tomorrow unavailable'),
    (today: false, tomorrow: false, name: 'today and tomorrow unavailable'),
  ]) {
    testWidgets(scenario.name, (tester) async {
      final tomorrow = TargetImagingAvailability(
        object: object,
        referenceDate: DateTime(2026, 9, 4),
        isAvailableTonight: scenario.tomorrow,
        primaryReason: scenario.tomorrow ? null : '고도 부족',
      );
      await tester.pumpWidget(MaterialApp(
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
      ));

      expect(find.text('오늘 9/3'), findsOneWidget);
      expect(find.text('내일 9/4'), findsOneWidget);
      expect(find.text('· 기상정보 미반영'), findsOneWidget);
      expect(find.text('8월 ~ 2월'), findsOneWidget);
      expect(find.text('10월 ~ 12월'), findsOneWidget);
      if (!scenario.tomorrow) {
        expect(find.text('고도 부족'), findsOneWidget);
      }
    });
  }
}
