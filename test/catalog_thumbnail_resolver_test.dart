import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/services/catalog_thumbnail_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogThumbnailResolver asset mapping', () {
    test('maps M1 to the zero-padded Messier asset', () {
      expect(
        CatalogThumbnailResolver.thumbnailAssetFor(_object('M1')),
        'assets/catalog/thumbnails/m001.webp',
      );
    });

    test('maps M16 to the zero-padded Messier asset', () {
      expect(
        CatalogThumbnailResolver.thumbnailAssetFor(_object('M16')),
        'assets/catalog/thumbnails/m016.webp',
      );
    });

    test('maps M110 to the final Messier asset', () {
      expect(
        CatalogThumbnailResolver.thumbnailAssetFor(_object('M110')),
        'assets/catalog/thumbnails/m110.webp',
      );
    });

    test('maps NGC7000 to its reviewed asset', () {
      expect(
        CatalogThumbnailResolver.thumbnailAssetFor(_object('NGC7000')),
        'assets/catalog/thumbnails/ngc7000.webp',
      );
    });

    test('maps IC5070 to its reviewed asset', () {
      expect(
        CatalogThumbnailResolver.thumbnailAssetFor(_object('IC5070')),
        'assets/catalog/thumbnails/ic5070.webp',
      );
    });

    test('maps Sh2-240 using the on-disk hyphen convention', () {
      expect(
        CatalogThumbnailResolver.thumbnailAssetFor(_object('Sh2-240')),
        'assets/catalog/thumbnails/sh2-240.webp',
      );
    });

    test('maps C14 using the on-disk Caldwell padding convention', () {
      expect(
        CatalogThumbnailResolver.thumbnailAssetFor(_object('C14')),
        'assets/catalog/thumbnails/c014.webp',
      );
    });

    test('returns null for a catalog object without a reviewed asset', () {
      expect(
        CatalogThumbnailResolver.thumbnailAssetFor(_object('NGC9999')),
        isNull,
      );
    });

    test('uses primaryCatalogId before the secondary object id', () {
      final secondary = _object('NGC1976', primaryCatalogId: 'M42');

      expect(
        CatalogThumbnailResolver.thumbnailAssetFor(secondary),
        'assets/catalog/thumbnails/m042.webp',
      );
    });
  });

  group('CatalogThumbnailResolver display priority', () {
    test('selects a user photo before the bundled asset', () {
      final selection = CatalogThumbnailResolver.resolve(
        _object('M31'),
        userPhotoPath: 'C:/photos/m31.webp',
      );

      expect(selection.source, CatalogThumbnailSource.userPhoto);
      expect(selection.path, 'C:/photos/m31.webp');
    });

    test('selects the bundled asset when there is no user photo', () {
      final selection = CatalogThumbnailResolver.resolve(_object('M31'));

      expect(selection.source, CatalogThumbnailSource.asset);
      expect(selection.path, 'assets/catalog/thumbnails/m031.webp');
    });

    test('keeps the existing fallback when neither image exists', () {
      final selection = CatalogThumbnailResolver.resolve(_object('NGC9999'));

      expect(selection.source, CatalogThumbnailSource.fallback);
      expect(selection.path, isNull);
    });

    test('shares representative-first selection across canonical aliases', () {
      final primary = _object('M42');
      final secondary = _object('NGC1976', primaryCatalogId: 'M42');
      final records = [
        _record(
          id: 'latest',
          catalogId: 'M42',
          photoUri: 'C:/photos/latest.webp',
          capturedAt: DateTime(2026, 9, 24),
        ),
        _record(
          id: 'representative',
          catalogId: 'NGC1976',
          photoUri: 'C:/photos/representative.webp',
          capturedAt: DateTime(2026, 9, 20),
          isRepresentative: true,
        ),
      ];

      final index = CatalogThumbnailResolver.buildUserPhotoIndex(
        records: records,
        catalog: [primary, secondary],
      );

      expect(
        CatalogThumbnailResolver.userPhotoFor(primary, index),
        'C:/photos/representative.webp',
      );
      expect(
        CatalogThumbnailResolver.userPhotoFor(secondary, index),
        'C:/photos/representative.webp',
      );
    });

    test('uses the newest photo when no representative is marked', () {
      final object = _object('M31');
      final records = [
        _record(
          id: 'older',
          catalogId: 'M31',
          photoUri: 'C:/photos/older.webp',
          capturedAt: DateTime(2026, 9, 20),
        ),
        _record(
          id: 'newer',
          catalogId: 'M31',
          photoUri: 'C:/photos/newer.webp',
          capturedAt: DateTime(2026, 9, 24),
        ),
      ];

      final index = CatalogThumbnailResolver.buildUserPhotoIndex(
        records: records,
        catalog: [object],
      );

      expect(
        CatalogThumbnailResolver.userPhotoFor(object, index),
        'C:/photos/newer.webp',
      );
    });
  });
}

CatalogObject _object(String id, {String? primaryCatalogId}) => CatalogObject(
  id: id,
  number: _numberFrom(id),
  catalog: _catalogFrom(id),
  name: id,
  type: '은하',
  constellation: '-',
  ra: '00:00:00',
  dec: '+00:00:00',
  magnitude: '-',
  isPrimaryCatalog: primaryCatalogId == null,
  primaryCatalogId: primaryCatalogId,
);

ShootingRecord _record({
  required String id,
  required String catalogId,
  required String photoUri,
  required DateTime capturedAt,
  bool isRepresentative = false,
}) => ShootingRecord(
  id: id,
  celestialObjectId: catalogId,
  capturedAt: capturedAt,
  createdAt: capturedAt,
  photoUri: photoUri,
  isRepresentative: isRepresentative,
);

int _numberFrom(String id) =>
    int.tryParse(RegExp(r'\d+').firstMatch(id)?.group(0) ?? '') ?? 0;

CatalogType _catalogFrom(String id) {
  final normalized = id.toUpperCase();
  if (normalized.startsWith('NGC')) return CatalogType.ngc;
  if (normalized.startsWith('IC')) return CatalogType.ic;
  if (normalized.startsWith('SH2-')) return CatalogType.sh2;
  if (normalized.startsWith('C')) return CatalogType.caldwell;
  return CatalogType.messier;
}
