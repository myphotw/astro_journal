import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/plate_solve_result.dart';
import 'package:astro_journal/data/models/photo_overlay_object.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/features/gallery/widgets/photo_overlay_view.dart';
import 'package:astro_journal/services/photo_overlay_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'durable field degrees and arcsec per pixel recover source dimensions',
    () {
      final dimensions = PhotoOverlayService.inferImageDimensions(
        PlateSolveResult.success(pixelScale: 2.4, fovWidth: 2, fovHeight: 1.5),
      );

      expect(dimensions, (3000, 2250));
      expect(
        PhotoOverlayService.inferImageDimensions(
          PlateSolveResult.success(fovWidth: 2, fovHeight: 1.5),
        ),
        isNull,
      );
    },
  );

  test('catalog diameter in arcmin becomes pixel radius', () async {
    final object = _object(id: 'M1', majorAxis: 60, minorAxis: 30);
    final result = await PhotoOverlayService(
      _CatalogRepository([object]),
    ).buildOverlay(_remoteRecord());

    expect(result.isAvailable, isTrue);
    expect(result.imageWidth, 1000);
    expect(result.imageHeight, 500);
    expect(result.objects.single.rangeRadiusMajorPixel, closeTo(500, 1e-9));
    expect(result.objects.single.rangeRadiusMinorPixel, closeTo(250, 1e-9));
  });

  test(
    'degree and arcsecond catalog strings normalize to arcminutes',
    () async {
      final degree = _object(id: 'DEG', angularSize: '1°');
      final arcsecond = _object(id: 'ARCSEC', angularSize: '60"');
      final result = await PhotoOverlayService(
        _CatalogRepository([degree, arcsecond]),
      ).buildOverlay(_remoteRecord(celestialObjectId: 'DEG'));
      final byId = {for (final object in result.objects) object.id: object};

      expect(byId['DEG']?.angularSizeMajor, 60);
      expect(byId['DEG']?.rangeRadiusMajorPixel, closeTo(500, 1e-9));
      expect(byId['ARCSEC']?.angularSizeMajor, 1);
      expect(byId['ARCSEC']?.rangeRadiusMajorPixel, closeTo(8.333333, 1e-5));
    },
  );

  test('BoxFit contain rect includes vertical letterbox offsets', () {
    final rect = photoOverlayContainRect(
      viewport: const Size(1000, 1000),
      source: const Size(1000, 500),
    );

    expect(rect, const Rect.fromLTWH(0, 250, 1000, 500));
  });

  group('angular-size render geometry', () {
    test('2px radius is not enlarged and gets a separate center marker', () {
      final geometry = photoOverlayRenderGeometry(
        _overlayObject(majorRadius: 2, minorRadius: 1),
        scale: 1,
      );

      expect(geometry.radiusX, 2);
      expect(geometry.radiusY, 1);
      expect(geometry.drawRing, isTrue);
      expect(geometry.drawCenterMarker, isTrue);
    });

    test('medium radius uses the exact projected size', () {
      final geometry = photoOverlayRenderGeometry(
        _overlayObject(majorRadius: 20, minorRadius: 12),
        scale: 0.5,
      );

      expect(geometry.radiusX, 10);
      expect(geometry.radiusY, 6);
      expect(geometry.drawCenterMarker, isFalse);
    });

    test('large radius is not reduced to a viewport fraction', () {
      final geometry = photoOverlayRenderGeometry(
        _overlayObject(majorRadius: 5000, minorRadius: 3000),
        scale: 1,
      );

      expect(geometry.radiusX, 5000);
      expect(geometry.radiusY, 3000);
      expect(geometry.drawRing, isTrue);
    });

    test('major and minor axes remain independent ellipse radii', () {
      final geometry = photoOverlayRenderGeometry(
        _overlayObject(majorRadius: 30, minorRadius: 10),
        scale: 2,
      );

      expect(geometry.radiusX, 60);
      expect(geometry.radiusY, 20);
    });

    test('missing minor axis falls back to a circular ring', () {
      final geometry = photoOverlayRenderGeometry(
        _overlayObject(majorRadius: 7),
        scale: 1,
      );

      expect(geometry.radiusX, 7);
      expect(geometry.radiusY, 7);
      expect(geometry.drawRing, isTrue);
    });

    test('unknown angular size draws only the position marker', () {
      final geometry = photoOverlayRenderGeometry(_overlayObject(), scale: 1);

      expect(geometry.drawRing, isFalse);
      expect(geometry.drawCenterMarker, isTrue);
    });
  });

  testWidgets('remote preview uses a network image provider', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: PhotoOverlayView(
            photoPath: 'https://backend.test/preview.jpg',
            imageWidth: 1000,
            imageHeight: 500,
          ),
        ),
      ),
    );

    expect(
      _baseProvider(tester.widget<Image>(find.byType(Image)).image),
      isA<NetworkImage>(),
    );
  });

  testWidgets('local preview uses a file image provider', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: PhotoOverlayView(
            photoPath: r'C:\photos\m42.jpg',
            imageWidth: 1000,
            imageHeight: 500,
          ),
        ),
      ),
    );

    expect(
      _baseProvider(tester.widget<Image>(find.byType(Image)).image),
      isA<FileImage>(),
    );
  });
}

ImageProvider _baseProvider(ImageProvider provider) {
  return provider is ResizeImage ? provider.imageProvider : provider;
}

PhotoOverlayObject _overlayObject({double? majorRadius, double? minorRadius}) {
  return PhotoOverlayObject(
    id: 'M1',
    photoId: 'photo-1',
    catalogId: 'M1',
    name: 'M1',
    commonName: 'Crab Nebula',
    objectType: 'Nebula',
    ra: 180,
    dec: 0,
    pixelX: 500,
    pixelY: 250,
    isTarget: true,
    rangeRadiusMajorPixel: majorRadius,
    rangeRadiusMinorPixel: minorRadius,
  );
}

ShootingRecord _remoteRecord({String celestialObjectId = 'M1'}) {
  return ShootingRecord(
    id: 'remote:record-1',
    celestialObjectId: celestialObjectId,
    capturedAt: DateTime.utc(2026, 8, 28),
    createdAt: DateTime.utc(2026, 8, 28),
    photoUri: 'https://backend.test/preview.jpg',
    plateSolve: PlateSolveResult.success(
      centerRa: 180,
      centerDec: 0,
      rotation: 0,
      parity: 1,
      pixelScale: 3.6,
      fovWidth: 1,
      fovHeight: 0.5,
    ),
  );
}

CatalogObject _object({
  required String id,
  String? angularSize,
  double? majorAxis,
  double? minorAxis,
}) {
  return CatalogObject(
    id: id,
    number: 1,
    catalog: CatalogType.messier,
    name: id,
    type: 'Nebula',
    constellation: 'Ori',
    ra: '12h 00m',
    dec: '+00° 00m',
    magnitude: '5',
    angularSize: angularSize,
    majorAxis: majorAxis,
    minorAxis: minorAxis,
  );
}

class _CatalogRepository extends Fake implements CatalogRepository {
  _CatalogRepository(this.objects);

  final List<CatalogObject> objects;

  @override
  Future<List<CatalogObject>> findObjectsInPhotoField({
    required double centerRaDeg,
    required double centerDecDeg,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required double rotationDeg,
  }) async => objects;

  @override
  Future<CatalogObject?> getById(String id) async {
    for (final object in objects) {
      if (object.id == id) return object;
    }
    return null;
  }

  @override
  Future<List<CatalogCandidate>> findNearbyObjects({
    required double raDeg,
    required double decDeg,
    required double radiusDeg,
  }) async => const [];
}
