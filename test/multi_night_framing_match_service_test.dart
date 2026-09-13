import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/multi_night_framing_reference.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/services/multi_night_framing_match_service.dart';
import 'package:astro_journal/services/equipment/field_orientation_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = MultiNightFramingMatchService(
    darkWindowResolver: _wholeDayDarkWindow,
  );

  test('reference derives signed HA, PA, and branch without user input', () {
    final reference = service.buildReference(
      object: _m16,
      capturedAt: DateTime(2026, 7, 15, 21, 10),
      site: _site,
      equipment: _equipment,
      id: _referenceId,
    );

    expect(reference.id, _referenceId);
    expect(reference.catalogObjectId, _m16.effectivePrimaryId);
    expect(reference.referenceHourAngleDeg, inInclusiveRange(-180, 180));
    expect(reference.referenceParallacticAngleDeg, inInclusiveRange(-180, 180));
    expect(
      reference.referenceBranch,
      MultiNightFramingMatchService.branchForHourAngle(
        reference.referenceHourAngleDeg,
      ),
    );
    expect(
      reference.toCreateJson()['reference_captured_at'].toString(),
      matches(RegExp(r'(Z|[+-]\d\d:\d\d)$')),
    );
  });

  test('same HA is reproduced on another date and after 14 days', () {
    final reference = service.buildReference(
      object: _m16,
      capturedAt: DateTime(2026, 7, 15, 21, 10),
      site: _site.copyWith(defaultMinAltitude: -90),
      equipment: _equipment,
      id: _referenceId,
    );
    for (final day in [16, 29]) {
      final result = service.findToday(
        object: _m16,
        reference: reference,
        site: _site.copyWith(defaultMinAltitude: -90),
        equipment: _equipment,
        today: DateTime(2026, 7, day),
      );
      expect(result.isAvailable, isTrue);
      expect(
        MultiNightFramingMatchService.circularAngleDifferenceDegrees(
          result.hourAngleDeg,
          reference.referenceHourAngleDeg,
        ),
        lessThan(0.01),
      );
      expect(
        MultiNightFramingMatchService.branchForHourAngle(result.hourAngleDeg),
        reference.referenceBranch,
      );
      expect(result.parallacticAngleDifferenceDeg, lessThan(0.02));
    }
  });

  test('rising and setting branches are preserved', () {
    for (final branch in MultiNightFramingBranch.values) {
      final reference = _reference(branch: branch);
      final result = service.findToday(
        object: _m16,
        reference: reference,
        site: _site.copyWith(defaultMinAltitude: -90),
        equipment: _equipment,
        today: DateTime(2026, 7, 16),
      );
      expect(result.isAvailable, isTrue);
      expect(
        MultiNightFramingMatchService.branchForHourAngle(result.hourAngleDeg),
        branch,
      );
    }
  });

  test('circular PA difference treats 179 and -179 as two degrees', () {
    expect(
      MultiNightFramingMatchService.circularAngleDifferenceDegrees(179, -179),
      2,
    );
  });

  test('site longitude changes the recommended local time', () {
    final reference = _reference();
    final first = service.findToday(
      object: _m16,
      reference: reference,
      site: _site.copyWith(defaultMinAltitude: -90),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );
    final second = service.findToday(
      object: _m16,
      reference: reference,
      site: _site.copyWith(longitude: 137, defaultMinAltitude: -90),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );

    expect(first.recommendedAt, isNot(second.recommendedAt));
  });

  test('altitude and blocked azimuth make an exact HA unavailable', () {
    final reference = _reference();
    final highMinimum = service.findToday(
      object: _m16,
      reference: reference,
      site: _site.copyWith(defaultMinAltitude: 90),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );
    final blocked = service.findToday(
      object: _m16,
      reference: reference,
      site: _site.copyWith(
        defaultMinAltitude: -90,
        blockedAzimuthRanges: const [
          BlockedAzimuthRange(
            id: 'blocked',
            observationSiteId: _siteId,
            startAzimuth: 0,
            endAzimuth: 359.999,
          ),
        ],
      ),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );

    expect(highMinimum.isAvailable, isFalse);
    expect(blocked.isAvailable, isFalse);
  });

  test('directional maximum altitude makes an exact HA unavailable', () {
    final result = service.findToday(
      object: _m16,
      reference: _reference(),
      site: _site.copyWith(
        defaultMinAltitude: -90,
        horizonPoints: const [
          HorizonPoint(
            id: 'ceiling',
            observationSiteId: _siteId,
            azimuth: 0,
            minAltitude: 0,
            maxAltitude: 0,
          ),
        ],
      ),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );

    expect(result.isAvailable, isFalse);
  });

  test('recommended range obeys the single PA tolerance', () {
    final result = service.findToday(
      object: _m16,
      reference: _reference(),
      site: _site.copyWith(defaultMinAltitude: -90),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );

    expect(result.isAvailable, isTrue);
    expect(result.rangeStart, isNotNull);
    expect(result.rangeEnd, isNotNull);
    expect(result.rangeStart!.isAfter(result.rangeEnd!), isFalse);
  });

  test('exact HA before dark time is not returned as a recommendation', () {
    final baseline = service.findToday(
      object: _m16,
      reference: _reference(),
      site: _site.copyWith(defaultMinAltitude: -90),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );
    final framingTime = baseline.framingMatchAt!;
    final darkStart = baseline.rangeEnd!.add(const Duration(hours: 1));
    final subject = MultiNightFramingMatchService(
      darkWindowResolver: _fixedDarkWindow(
        date: DateTime(2026, 7, 16),
        start: darkStart,
        end: darkStart.add(const Duration(hours: 1)),
      ),
    );

    final result = subject.findToday(
      object: _m16,
      reference: _reference(),
      site: _site.copyWith(defaultMinAltitude: -90),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );

    expect(result.isAvailable, isFalse);
    expect(result.recommendedAt, isNull);
    expect(result.framingMatchAt, framingTime);
    expect(
      result.unavailableCause,
      MultiNightFramingUnavailableCause.skyTooBright,
    );
    expect(result.darkStart, darkStart);
  });

  test('only the dark intersection of the PA range is recommended', () {
    final baseline = service.findToday(
      object: _m16,
      reference: _reference(),
      site: _site.copyWith(defaultMinAltitude: -90),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );
    final darkStart = baseline.framingMatchAt!.add(const Duration(minutes: 1));
    final darkEnd = baseline.rangeEnd!;
    final subject = MultiNightFramingMatchService(
      darkWindowResolver: _fixedDarkWindow(
        date: DateTime(2026, 7, 16),
        start: darkStart,
        end: darkEnd,
      ),
    );

    final result = subject.findToday(
      object: _m16,
      reference: _reference(),
      site: _site.copyWith(defaultMinAltitude: -90),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );

    expect(result.isAvailable, isTrue);
    expect(result.rangeStart, darkStart);
    expect(result.rangeEnd, darkEnd);
    expect(result.recommendedAt, darkStart);
    expect(result.framingMatchAt!.isBefore(result.recommendedAt!), isTrue);
  });

  test('times after the morning dark window are excluded', () {
    final morningReference = service.buildReference(
      object: _m16,
      capturedAt: DateTime(2026, 7, 15, 4),
      site: _site.copyWith(defaultMinAltitude: -90),
      equipment: _equipment,
      id: 'morning-reference',
    );
    final baseline = service.findToday(
      object: _m16,
      reference: morningReference,
      site: _site.copyWith(defaultMinAltitude: -90),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );
    final darkEnd = baseline.rangeStart!.subtract(const Duration(minutes: 1));
    final subject = MultiNightFramingMatchService(
      darkWindowResolver: _fixedDarkWindow(
        date: DateTime(2026, 7, 16),
        start: darkEnd.subtract(const Duration(hours: 2)),
        end: darkEnd,
      ),
    );

    final result = subject.findToday(
      object: _m16,
      reference: morningReference,
      site: _site.copyWith(defaultMinAltitude: -90),
      equipment: _equipment,
      today: DateTime(2026, 7, 16),
    );

    expect(result.isAvailable, isFalse);
    expect(result.recommendedAt, isNull);
    expect(result.unavailableCause, MultiNightFramingUnavailableCause.dawn);
  });
}

MultiNightDarkWindow _wholeDayDarkWindow(DateTime date) {
  final start = DateTime(date.year, date.month, date.day);
  return (nightStart: start, nightEnd: start.add(const Duration(days: 1)));
}

MultiNightDarkWindowResolver _fixedDarkWindow({
  required DateTime date,
  required DateTime start,
  required DateTime end,
}) => (requestedDate) {
  if (requestedDate.year == date.year &&
      requestedDate.month == date.month &&
      requestedDate.day == date.day) {
    return (nightStart: start, nightEnd: end);
  }
  final previous = DateTime(
    requestedDate.year,
    requestedDate.month,
    requestedDate.day,
  );
  return (nightStart: previous, nightEnd: previous);
};

const _referenceId = '11111111-1111-4111-8111-111111111111';
const _siteId = '22222222-2222-4222-8222-222222222222';
const _equipmentId = '33333333-3333-4333-8333-333333333333';

const _m16 = CatalogObject(
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

final _site = ObservationSite(
  id: _siteId,
  name: '집',
  latitude: 37.5,
  longitude: 127,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

const _equipment = Equipment(
  id: _equipmentId,
  name: 'Draco',
  kind: EquipmentKind.smartTelescope,
  purpose: EquipmentPurpose.imaging,
);

MultiNightFramingReference _reference({
  MultiNightFramingBranch branch = MultiNightFramingBranch.rising,
}) => MultiNightFramingReference(
  id: _referenceId,
  catalogObjectId: 'M16',
  referenceCapturedAt: DateTime(2026, 7, 15, 21, 10),
  siteId: _siteId,
  equipmentId: _equipmentId,
  referenceHourAngleDeg: branch == MultiNightFramingBranch.rising ? -20 : 20,
  referenceParallacticAngleDeg:
      FieldOrientationCalculator.parallacticAngleDegrees(
        latitudeDeg: 37.5,
        hourAngleDeg: branch == MultiNightFramingBranch.rising ? -20 : 20,
        declinationDeg: -13 - 47 / 60,
      ),
  referenceBranch: branch,
  revision: 1,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
