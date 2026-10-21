import 'dart:ui';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/site_horizon_profile.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/observation_site/viewmodel/active_observation_site_view_model.dart';
import 'package:astro_journal/features/sky_map/viewmodel/sky_map_view_model.dart';
import 'package:astro_journal/features/sky_map/widgets/painters/observation_site_horizon_painter.dart';
import 'package:astro_journal/services/sky_map_horizontal_projection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(800, 600);

  group('ObservationSiteHorizonPainter', () {
    test('uses registered minimum and maximum altitude restrictions', () {
      final painter = _painter(
        const SiteHorizonProfile(
          points: [
            HorizonPoint(
              id: 'north',
              observationSiteId: 'site',
              azimuth: 0,
              minAltitude: 20,
              maxAltitude: 70,
            ),
            HorizonPoint(
              id: 'east',
              observationSiteId: 'site',
              azimuth: 90,
              minAltitude: 30,
            ),
          ],
        ),
      );

      expect(painter.isMasked(azimuthDeg: 0, altitudeDeg: 10), isTrue);
      expect(painter.isMasked(azimuthDeg: 0, altitudeDeg: 45), isFalse);
      expect(painter.isMasked(azimuthDeg: 0, altitudeDeg: 80), isTrue);
      expect(painter.isMasked(azimuthDeg: 360, altitudeDeg: 10), isTrue);
    });

    test('supports wrapped and multiple blocked azimuth ranges', () {
      final painter = _painter(
        const SiteHorizonProfile(
          blockedRanges: [
            BlockedAzimuthRange(
              id: 'north-wrap',
              observationSiteId: 'site',
              startAzimuth: 350,
              endAzimuth: 20,
            ),
            BlockedAzimuthRange(
              id: 'south-east',
              observationSiteId: 'site',
              startAzimuth: 100,
              endAzimuth: 120,
            ),
          ],
        ),
      );

      expect(painter.isMasked(azimuthDeg: 0, altitudeDeg: 40), isTrue);
      expect(painter.isMasked(azimuthDeg: 355, altitudeDeg: 40), isTrue);
      expect(painter.isMasked(azimuthDeg: 110, altitudeDeg: 40), isTrue);
      expect(painter.isMasked(azimuthDeg: 200, altitudeDeg: 40), isFalse);
    });

    test('projects the boundary through the shared horizontal projection', () {
      const profile = SiteHorizonProfile(
        points: [
          HorizonPoint(
            id: 'west',
            observationSiteId: 'site',
            azimuth: 270,
            minAltitude: 25,
          ),
        ],
      );
      final painter = ObservationSiteHorizonPainter(
        profile: profile,
        centerAltitudeDeg: 35,
        centerAzimuthDeg: 250,
        viewHeightDeg: 50,
      );
      final expected = SkyMapHorizontalProjectionService.project(
        altitudeDeg: 25,
        azimuthDeg: 270,
        centerAltitudeDeg: 35,
        centerAzimuthDeg: 250,
        canvasSize: size,
        viewHeightDeg: 50,
      ).pixel;

      expect(
        painter.projectBoundaryPoint(
          azimuthDeg: 270,
          altitudeDeg: 25,
          size: size,
        ),
        expected,
      );
    });

    test('does nothing when the active site has no registered horizon', () {
      final painter = _painter(const SiteHorizonProfile());
      expect(painter.isMasked(azimuthDeg: 0, altitudeDeg: 10), isFalse);

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      expect(() => painter.paint(canvas, size), returnsNormally);
      recorder.endRecording().dispose();
    });

    test('renders registered profile without changing sky object data', () {
      final painter = _painter(
        const SiteHorizonProfile(
          points: [
            HorizonPoint(
              id: 'point',
              observationSiteId: 'site',
              azimuth: 180,
              minAltitude: 35,
            ),
          ],
          blockedRanges: [
            BlockedAzimuthRange(
              id: 'range',
              observationSiteId: 'site',
              startAzimuth: 350,
              endAzimuth: 15,
            ),
          ],
        ),
      );
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      expect(() => painter.paint(canvas, size), returnsNormally);
      recorder.endRecording().dispose();
    });
  });

  group('SkyMap observation-site horizon state', () {
    test('filter defaults on and toggles independently', () {
      const filters = SkyMapFilters();
      final hidden = filters.copyWith(showObservationSiteHorizon: false);

      expect(filters.showObservationSiteHorizon, isTrue);
      expect(hidden.showObservationSiteHorizon, isFalse);
      expect(hidden.showMilkyWay, filters.showMilkyWay);
      expect(hidden.showConstellations, filters.showConstellations);
      expect(hidden.catalogs, filters.catalogs);
    });

    test(
      'active observation-site changes expose the new profile immediately',
      () async {
        final activeSite = ActiveObservationSiteViewModel(_SiteRepository());
        final viewModel = SkyMapViewModel(
          _CatalogRepository(),
          _EquipmentRepository(),
          activeSite,
          () => DateTime(2026, 10, 21, 20),
        );
        var notifications = 0;
        viewModel.addListener(() => notifications++);

        expect(
          viewModel.observationSiteHorizonProfile.hasRestrictions,
          isFalse,
        );
        await activeSite.selectSavedSite(_siteWithHorizon());

        expect(viewModel.observationSiteHorizonProfile.points, hasLength(1));
        expect(
          viewModel.observationSiteHorizonProfile.blockedRanges,
          hasLength(1),
        );
        expect(notifications, greaterThan(0));
        viewModel.dispose();
      },
    );
  });
}

ObservationSiteHorizonPainter _painter(SiteHorizonProfile profile) =>
    ObservationSiteHorizonPainter(
      profile: profile,
      centerAltitudeDeg: 90,
      centerAzimuthDeg: 180,
      viewHeightDeg: 180,
    );

ObservationSite _siteWithHorizon() => ObservationSite(
  id: 'site',
  name: '집',
  latitude: 37.5,
  longitude: 127,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  horizonPoints: const [
    HorizonPoint(
      id: 'point',
      observationSiteId: 'site',
      azimuth: 180,
      minAltitude: 30,
    ),
  ],
  blockedAzimuthRanges: const [
    BlockedAzimuthRange(
      id: 'range',
      observationSiteId: 'site',
      startAzimuth: 350,
      endAzimuth: 20,
    ),
  ],
);

class _CatalogRepository implements CatalogRepository {
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

class _EquipmentRepository implements EquipmentRepository {
  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => const [];

  @override
  Future<Equipment?> getById(String id) async => null;

  @override
  Future<void> save(Equipment equipment) async {}

  @override
  Future<void> delete(String id) async {}
}

class _SiteRepository implements ObservationSiteRepository {
  @override
  Future<void> markLastUsed(String id, DateTime usedAt) async {}

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async =>
      const [];

  @override
  Future<ObservationSite?> get(
    String id, {
    bool includeDeleted = false,
  }) async => null;

  @override
  Future<void> create(ObservationSite site) async {}

  @override
  Future<void> createFavorite(ObservationSite site) async {}

  @override
  Future<void> update(ObservationSite site) async {}

  @override
  Future<void> delete(String id, {bool hard = false}) async {}

  @override
  Future<void> setFavorite(String id, bool favorite) async {}

  @override
  Future<List<HorizonPoint>> listHorizonPoints(String siteId) async => const [];

  @override
  Future<void> addHorizonPoint(HorizonPoint point) async {}

  @override
  Future<void> updateHorizonPoint(HorizonPoint point) async {}

  @override
  Future<void> deleteHorizonPoint(String id) async {}

  @override
  Future<void> replaceHorizonPoints(
    String siteId,
    List<HorizonPoint> points,
  ) async {}

  @override
  Future<List<BlockedAzimuthRange>> listBlockedRanges(String siteId) async =>
      const [];

  @override
  Future<void> addBlockedRange(BlockedAzimuthRange range) async {}

  @override
  Future<void> updateBlockedRange(BlockedAzimuthRange range) async {}

  @override
  Future<void> deleteBlockedRange(String id) async {}

  @override
  Future<void> replaceBlockedRanges(
    String siteId,
    List<BlockedAzimuthRange> ranges,
  ) async {}
}
