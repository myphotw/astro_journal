import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/features/sky_map/viewmodel/sky_map_view_model.dart';
import 'package:astro_journal/features/sky_map/widgets/sky_map_time_control.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/sky_map_night_timeline_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SkyMapTimeControl', () {
    testWidgets('shows local date and time without narrow overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 320,
                child: SkyMapTimeControl(
                  observationDate: DateTime(2026, 10, 20),
                  observationTime: DateTime(2026, 10, 20, 20),
                  timeline: _timeline(DateTime(2026, 10, 20)),
                  onDateChanged: (_) {},
                  onTimelineMinutesChanged: (_) {},
                  onNowPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('2026-10-20'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sky-map-midnight-marker')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sky-map-sunset-marker')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sky-map-sunrise-marker')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('date button opens calendar and returns the selected date', (
      tester,
    ) async {
      DateTime? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SkyMapTimeControl(
              observationDate: DateTime(2026, 10, 20),
              observationTime: DateTime(2026, 10, 20, 20),
              timeline: _timeline(DateTime(2026, 10, 20)),
              onDateChanged: (value) => selected = value,
              onTimelineMinutesChanged: (_) {},
              onNowPressed: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('sky-map-date-button')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await tester.tap(find.text('21'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(selected, DateTime(2026, 10, 21));
    });

    testWidgets('slider emits ten-minute values and current button is active', (
      tester,
    ) async {
      int? minutes;
      var reset = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SkyMapTimeControl(
              observationDate: DateTime(2026, 10, 20),
              observationTime: DateTime(2026, 10, 20, 20),
              timeline: _timeline(DateTime(2026, 10, 20)),
              onDateChanged: (_) {},
              onTimelineMinutesChanged: (value) => minutes = value,
              onNowPressed: () => reset = true,
            ),
          ),
        ),
      );

      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('sky-map-time-slider')),
      );
      slider.onChanged!(613);
      expect(minutes, 610);

      await tester.tap(find.byKey(const ValueKey('sky-map-now-button')));
      expect(reset, isTrue);
    });
  });

  group('SkyMapViewModel observation time', () {
    testWidgets('initializes to now and date changes preserve selected time', (
      tester,
    ) async {
      final now = DateTime(2026, 10, 20, 20, 37);
      final vm = _viewModel(now, objects: [_object()]);
      await tester.runAsync(vm.load);
      vm.updateCanvasSize(const Size(900, 600));
      final beforeAltitude = vm.visibleObjects.single.altitudeDeg;

      expect(vm.observationTime, now);
      expect(vm.isFollowingCurrentTime, isTrue);

      vm.setObservationDate(DateTime(2026, 11, 5));
      await tester.pump();

      expect(vm.observationTime, DateTime(2026, 11, 5, 20, 37));
      expect(vm.isFollowingCurrentTime, isFalse);
      expect(vm.visibleObjects.single.altitudeDeg, isNot(beforeAltitude));
      vm.dispose();
    });

    testWidgets('slider time changes real sky while preserving view state', (
      tester,
    ) async {
      final now = DateTime(2026, 10, 20, 18);
      final object = _object();
      final vm = _viewModel(now, objects: [object]);
      await tester.runAsync(vm.load);
      vm.updateCanvasSize(const Size(900, 600));
      vm.selectObject(object);
      vm.setViewHeightDeg(90);
      await tester.pump();
      final centerAzimuth = vm.centerAzimuthDeg;
      final centerAltitude = vm.centerAltitudeDeg;
      final viewHeight = vm.viewHeightDeg;
      final filters = vm.filters;
      final beforeAltitude = vm.selectedRenderObject!.altitudeDeg;
      final beforeSunAltitude = vm.sunAltitudeDeg;

      vm.setObservationTimelineMinutes(
        vm.nightTimeline.offsetFor(DateTime(2026, 10, 20, 20)),
      );
      await tester.pump();

      expect(vm.observationTime, DateTime(2026, 10, 20, 20));
      expect(vm.selectedObject, same(object));
      expect(vm.centerAzimuthDeg, centerAzimuth);
      expect(vm.centerAltitudeDeg, centerAltitude);
      expect(vm.viewHeightDeg, viewHeight);
      expect(vm.filters, same(filters));
      expect(vm.selectedRenderObject!.altitudeDeg, isNot(beforeAltitude));
      expect(vm.sunAltitudeDeg, isNot(beforeSunAltitude));
      vm.dispose();
    });

    testWidgets('rapid changes apply only the latest observation time', (
      tester,
    ) async {
      final object = _object();
      final vm = _viewModel(DateTime(2026, 10, 20, 20), objects: [object]);
      await tester.runAsync(vm.load);
      vm.updateCanvasSize(const Size(900, 600));

      vm.setObservationTimelineMinutes(
        vm.nightTimeline.offsetFor(DateTime(2026, 10, 20, 20)),
      );
      vm.setObservationTimelineMinutes(
        vm.nightTimeline.offsetFor(DateTime(2026, 10, 20, 20, 10)),
      );
      vm.setObservationTimelineMinutes(
        vm.nightTimeline.offsetFor(DateTime(2026, 10, 20, 20, 20)),
      );
      await tester.pump();

      expect(vm.observationTime, DateTime(2026, 10, 20, 20, 20));
      final expected = CelestialPositionService.computeAltAz(
        raHours: 5,
        decDeg: 20,
        latDeg: 0,
        lonDeg: 0,
        time: vm.observationTime,
      );
      expect(
        vm.visibleObjects.single.altitudeDeg,
        closeTo(expected.altitude, 1e-9),
      );
      vm.dispose();
    });

    testWidgets('current restores the injected clock after manual selection', (
      tester,
    ) async {
      final now = DateTime(2026, 10, 20, 21, 43);
      final vm = _viewModel(now);
      await tester.runAsync(vm.load);
      vm.setObservationTimelineMinutes(vm.nightTimeline.midnightOffsetMinutes);
      await tester.pump();
      expect(vm.observationTime, DateTime(2026, 10, 21));

      vm.setObservationTimelineMinutes(
        vm.nightTimeline.midnightOffsetMinutes + 10,
      );
      await tester.pump();
      expect(vm.observationTime, DateTime(2026, 10, 21, 0, 10));

      vm.resetObservationTime();
      await tester.pump();

      expect(vm.observationTime, now);
      expect(vm.isFollowingCurrentTime, isTrue);
      vm.dispose();
    });

    testWidgets(
      'early morning current time belongs to previous observing day',
      (tester) async {
        final now = DateTime(2026, 10, 21, 2, 30);
        final vm = _viewModel(now);
        await tester.runAsync(vm.load);

        expect(vm.observationDate, DateTime(2026, 10, 20));
        expect(vm.observationTime, now);
        expect(
          SkyMapTimeControl.formatTimeWithDayOffset(
            vm.observationTime,
            vm.observationDate,
          ),
          '02:30 (+1일)',
        );
        vm.dispose();
      },
    );
  });
}

SkyMapNightTimeline _timeline(DateTime date) =>
    const SkyMapNightTimelineService().calculate(
      observationDate: date,
      latitudeDeg: 37.5665,
      longitudeDeg: 126.978,
    );

SkyMapViewModel _viewModel(
  DateTime now, {
  List<CatalogObject> objects = const [],
}) => SkyMapViewModel(
  _FakeCatalogRepository(objects),
  _FakeEquipmentRepository(),
  null,
  () => now,
);

CatalogObject _object() => const CatalogObject(
  id: 'M-test',
  number: 999,
  catalog: CatalogType.messier,
  name: 'M-test',
  commonName: 'Time target',
  type: '은하',
  objectType: '은하',
  constellation: '오리온자리',
  ra: '5h0m',
  dec: '+20d0m',
  magnitude: '5',
);

class _FakeCatalogRepository implements CatalogRepository {
  _FakeCatalogRepository(this.objects);

  final List<CatalogObject> objects;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => objects;

  @override
  Future<CatalogObject?> getById(String id) async => null;

  @override
  Future<List<CatalogObject>> getByCatalog(CatalogType type) async => const [];

  @override
  Future<List<CatalogObject>> search(String query, {int limit = 50}) async =>
      const [];

  @override
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {}

  @override
  Future<void> insert(CatalogObject object) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<CatalogCandidate>> findNearbyObjects({
    required double raDeg,
    required double decDeg,
    required double radiusDeg,
  }) async => const [];

  @override
  Future<List<CatalogObject>> findObjectsInPhotoField({
    required double centerRaDeg,
    required double centerDecDeg,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required double rotationDeg,
  }) async => const [];
}

class _FakeEquipmentRepository implements EquipmentRepository {
  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => const [];

  @override
  Future<Equipment?> getById(String id) async => null;

  @override
  Future<void> save(Equipment equipment) async {}

  @override
  Future<void> delete(String id) async {}
}
