import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/object_observation_window.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/services/equipment/alt_az_imaging_policy.dart';
import 'package:astro_journal/services/equipment/field_orientation_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = AltAzImagingPolicy();
  const latitude = 37.5;
  const longitude = 127.0;

  ObservationContext context(DateTime start) => ObservationContext(
        latitude: latitude,
        longitude: longitude,
        moonIllumination: 0.1,
        moonAltitude: -10,
        moonAzimuth: 180,
        cloudCover: 0,
        observationStart: start,
        observationEnd: start.add(const Duration(hours: 6)),
        currentTime: start,
      );

  List<DateTime> slots(DateTime start, int count) => List.generate(
        count,
        (index) => start.add(Duration(minutes: index * 10)),
      );

  ObjectObservationWindow window({
    required List<DateTime> geometric,
    List<DateTime>? feasible,
  }) {
    final actual = feasible ?? geometric;
    return ObjectObservationWindow(
      currentAltitude: 50,
      currentAzimuth: 180,
      isCurrentlyVisible: true,
      recommendStartTime: actual.first,
      observationEndTime: actual.last,
      totalObservableMinutes: actual.length * 10,
      geometricSlotStarts: geometric,
      slotObservationScores: {for (final slot in actual) slot: 80},
    );
  }

  String raLabel(double hours) {
    final normalized = (hours % 24 + 24) % 24;
    final whole = normalized.floor();
    final minutes = ((normalized - whole) * 60).round();
    return '${(whole + minutes ~/ 60) % 24}h ${minutes % 60}m';
  }

  CatalogObject target({required String id, required String ra, required String dec}) =>
      CatalogObject(
        id: id,
        number: 1,
        catalog: CatalogType.messier,
        name: id,
        type: '발광성운',
        constellation: 'Test',
        ra: ra,
        dec: dec,
        magnitude: '6.0',
      );

  test('EQ keeps the existing total recommended duration', () {
    final start = DateTime(2026, 10, 1, 20);
    final result = policy.calculate(
      object: target(id: 'EQ', ra: '5h 0m', dec: '+20° 0m'),
      context: context(start),
      window: window(geometric: slots(start, 24)),
      trackingMode: TrackingMode.eq,
      minimumExposure: const Duration(minutes: 30),
      recommendedTotalExposure: const Duration(minutes: 180),
    );

    expect(result.recommendedDailyExposure, const Duration(minutes: 180));
    expect(result.dailyDurationLimitedByFieldRotation, isFalse);
    expect(result.preferredHaWindow, isNull);
  });

  test('high Alt-Az rotation shortens daily duration relative to low rotation', () {
    final start = DateTime(2026, 10, 1, 20);
    final middle = start.add(const Duration(hours: 2));
    final lstHours = FieldOrientationCalculator.hourAngleDegrees(
          longitudeDeg: longitude,
          time: middle,
          raHours: 0,
        ) /
        15;
    final geometric = slots(start, 24);
    final highRotation = policy.calculate(
      object: target(
        id: 'HIGH',
        ra: raLabel(lstHours),
        dec: '+37° 30m',
      ),
      context: context(start),
      window: window(geometric: geometric),
      trackingMode: TrackingMode.altAz,
      minimumExposure: const Duration(minutes: 30),
      recommendedTotalExposure: const Duration(minutes: 240),
    );
    final lowRotation = policy.calculate(
      object: target(
        id: 'LOW',
        ra: raLabel(lstHours + 6),
        dec: '-20° 0m',
      ),
      context: context(start),
      window: window(geometric: geometric),
      trackingMode: TrackingMode.altAz,
      minimumExposure: const Duration(minutes: 30),
      recommendedTotalExposure: const Duration(minutes: 240),
    );

    expect(
      highRotation.recommendedDailyExposure,
      lessThan(lowRotation.recommendedDailyExposure),
    );
    expect(highRotation.dailyDurationLimitedByFieldRotation, isTrue);
  });

  test('daily duration never exceeds the current feasible visibility run', () {
    final start = DateTime(2026, 10, 1, 20);
    final geometric = slots(start, 24);
    final feasible = slots(start.add(const Duration(hours: 1)), 6);
    final result = policy.calculate(
      object: target(id: 'VISIBLE', ra: '5h 0m', dec: '+20° 0m'),
      context: context(start),
      window: window(geometric: geometric, feasible: feasible),
      trackingMode: TrackingMode.altAz,
      minimumExposure: const Duration(minutes: 30),
      recommendedTotalExposure: const Duration(minutes: 180),
    );

    expect(result.recommendedDailyExposure.inMinutes, lessThanOrEqualTo(60));
    expect(result.recommendedDailyExposure.inMinutes % 10, 0);
  });

  test('nearby dates derive a similar preferred HA window without history', () {
    final firstStart = DateTime(2026, 10, 1, 20);
    final secondStart = DateTime(2026, 10, 2, 19, 50);
    final object = target(id: 'REPEATABLE', ra: '22h 0m', dec: '+25° 0m');
    final first = policy.calculate(
      object: object,
      context: context(firstStart),
      window: window(geometric: slots(firstStart, 24)),
      trackingMode: TrackingMode.altAz,
      minimumExposure: const Duration(minutes: 30),
      recommendedTotalExposure: const Duration(minutes: 120),
    );
    final second = policy.calculate(
      object: object,
      context: context(secondStart),
      window: window(geometric: slots(secondStart, 24)),
      trackingMode: TrackingMode.altAz,
      minimumExposure: const Duration(minutes: 30),
      recommendedTotalExposure: const Duration(minutes: 120),
    );

    expect(first.preferredHaWindow, isNotNull);
    expect(second.preferredHaWindow, isNotNull);
    expect(first.preferredHaWindow!.todayStartTime, isNotNull);
    expect(first.preferredHaWindow!.todayEndTime, isNotNull);
    expect(
      first.preferredHaWindow!.todayEndTime!
          .difference(first.preferredHaWindow!.todayStartTime!),
      Duration(minutes: first.preferredHaWindow!.durationMinutes),
    );
    expect(
      FieldOrientationCalculator.hourAngleDistanceHours(
        first.preferredHaWindow!.centerHours,
        second.preferredHaWindow!.centerHours,
      ),
      lessThan(0.25),
    );
  });
}
