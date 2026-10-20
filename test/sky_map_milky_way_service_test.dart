import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/features/sky_map/viewmodel/sky_map_view_model.dart';
import 'package:astro_journal/features/sky_map/widgets/painters/milky_way_painter.dart';
import 'package:astro_journal/features/sky_map/widgets/sky_map_filter_sheet.dart';
import 'package:astro_journal/services/sky_map_milky_way_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SkyMapMilkyWayService', () {
    const service = SkyMapMilkyWayService();

    test('loads the visible-light texture and equatorial mesh', () async {
      final model = await service.load();

      expect(model.image.width, 1024);
      expect(model.image.height, 512);
      expect(model.longitudeCount, 121);
      expect(model.latitudeCount, 61);
      expect(model.equatorialCoordinates, hasLength(121 * 61));
      expect(model.textureCoordinates, hasLength(121 * 61));

      final rgba = await model.image.toByteData();
      expect(rgba, isNotNull);
      final alphaValues = <int>{};
      var minimumAlpha = 255;
      var maximumAlpha = 0;
      for (var index = 3; index < rgba!.lengthInBytes; index += 4) {
        final alpha = rgba.getUint8(index);
        alphaValues.add(alpha);
        if (alpha < minimumAlpha) minimumAlpha = alpha;
        if (alpha > maximumAlpha) maximumAlpha = alpha;
      }
      expect(minimumAlpha, 0);
      expect(maximumAlpha, greaterThan(180));
      expect(alphaValues.length, greaterThan(100));
    });

    test('texture mapping preserves the Stellarium orientation and seam', () {
      final seam = SkyMapMilkyWayService.textureCoordinateForEquatorial(
        raDeg: 90,
        decDeg: 90,
        width: 1024,
        height: 512,
      );
      final opposite = SkyMapMilkyWayService.textureCoordinateForEquatorial(
        raDeg: 270,
        decDeg: 0,
        width: 1024,
        height: 512,
      );
      final wrapped = SkyMapMilkyWayService.textureCoordinateForEquatorial(
        raDeg: 450,
        decDeg: 90,
        width: 1024,
        height: 512,
      );

      expect(seam, Offset.zero);
      expect(wrapped, Offset.zero);
      expect(opposite.dx, closeTo(512, 1e-9));
      expect(opposite.dy, closeTo(256, 1e-9));
    });

    test('Galactic center maps to the standard J2000 coordinate', () {
      final center = SkyMapMilkyWayService.galacticToEquatorial(
        longitudeDeg: 0,
        latitudeDeg: 0,
      );
      final wrapped = SkyMapMilkyWayService.galacticToEquatorial(
        longitudeDeg: 360,
        latitudeDeg: 0,
      );

      expect(center.raHours * 15, closeTo(266.405, 0.001));
      expect(center.decDeg, closeTo(-28.936, 0.001));
      expect(wrapped.raHours, closeTo(center.raHours, 1e-10));
      expect(wrapped.decDeg, closeTo(center.decDeg, 1e-10));
    });

    test('selected time rotates the same static sky mesh', () async {
      final model = await service.load();
      final evening = service.toHorizontal(
        model: model,
        time: DateTime(2026, 10, 20, 20),
        latitudeDeg: 37.5,
        longitudeDeg: 127,
      );
      final morning = service.toHorizontal(
        model: model,
        time: DateTime(2026, 10, 21, 2),
        latitudeDeg: 37.5,
        longitudeDeg: 127,
      );

      expect(evening.image, same(morning.image));
      expect(evening.textureCoordinates, same(morning.textureCoordinates));
      final equatorIndex = 30 * model.longitudeCount;
      expect(
        morning.coordinates[equatorIndex].azimuth,
        isNot(closeTo(evening.coordinates[equatorIndex].azimuth, 0.01)),
      );
    });

    test('view model omits the mesh while the filter is disabled', () async {
      final viewModel = SkyMapViewModel(
        _FakeCatalogRepository(),
        _FakeEquipmentRepository(),
      );
      await viewModel.load();
      expect(viewModel.milkyWay.isEmpty, isFalse);

      viewModel.setShowMilkyWay(false);

      expect(viewModel.filters.showMilkyWay, isFalse);
      expect(viewModel.milkyWay.isEmpty, isTrue);
      viewModel.dispose();
    });
  });

  group('MilkyWayPainter visibility', () {
    test('daylight and twilight visibility is continuous', () {
      expect(MilkyWayPainter.daylightVisibility(0), 0);
      expect(MilkyWayPainter.daylightVisibility(-6), 0);
      expect(MilkyWayPainter.daylightVisibility(-12), closeTo(0.34, 1e-9));
      expect(MilkyWayPainter.daylightVisibility(-18), closeTo(1, 1e-9));
      expect(MilkyWayPainter.daylightVisibility(-24), 1);
      expect(
        MilkyWayPainter.daylightVisibility(-12.001),
        closeTo(MilkyWayPainter.daylightVisibility(-11.999), 0.001),
      );
    });

    test('below-horizon brightness fades instead of cutting off', () {
      expect(MilkyWayPainter.horizonVisibility(2), 1);
      expect(MilkyWayPainter.horizonVisibility(-18), 0);
      expect(
        MilkyWayPainter.horizonVisibility(-0.001),
        closeTo(MilkyWayPainter.horizonVisibility(0.001), 0.001),
      );
      expect(
        MilkyWayPainter.horizonVisibility(-10),
        lessThan(MilkyWayPainter.horizonVisibility(-2)),
      );
    });

    testWidgets('filter exposes a default-on Milky Way switch', (tester) async {
      final viewModel = SkyMapViewModel(
        _FakeCatalogRepository(),
        _FakeEquipmentRepository(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showSkyMapFilterSheet(context: context, viewModel: viewModel),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '은하수'),
      );
      expect(tile.value, isTrue);

      tile.onChanged!(false);
      await tester.pump();
      expect(viewModel.filters.showMilkyWay, isFalse);
      viewModel.dispose();
    });
  });
}

class _FakeCatalogRepository implements CatalogRepository {
  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => const [];

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
