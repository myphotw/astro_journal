import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/exif_info.dart';
import 'package:astro_journal/data/models/photo_metadata.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/models/sync_outbox_item.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/gallery_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/data/repositories/sync_outbox_repository.dart';
import 'package:astro_journal/services/api_key_service.dart';
import 'package:astro_journal/services/exif_service.dart';
import 'package:astro_journal/services/geocoding_service.dart';
import 'package:astro_journal/services/catalog_capture_projection_service.dart';
import 'package:astro_journal/services/photo_registration_service.dart';
import 'package:astro_journal/services/photo_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'registration persists final upload target and corrected date',
    () async {
      final outbox = _CapturingOutbox();
      final records = _MemoryRecords();
      final catalog = _MemoryCatalog();
      final service = PhotoRegistrationService(
        photoService: _FakePhotoService(),
        geocodingService: GeocodingService(),
        apiKeyService: ApiKeyService(),
        exifService: ExifService(),
        shootingRecordRepository: records,
        catalogRepository: catalog,
        syncOutboxRepository: outbox,
      );
      const object = CatalogObject(
        id: 'M31',
        number: 31,
        catalog: CatalogType.messier,
        name: 'Andromeda Galaxy',
        commonName: 'Andromeda Galaxy',
        type: 'Galaxy',
        constellation: 'Andromeda',
        ra: '',
        dec: '',
        magnitude: '',
      );

      await service.registerPhotoRecord(
        payload: _payload(exifDate: '2026-08-15T22:00:00'),
        confirmed: const ConfirmedMetadata(capturedAt: '2026-08-17T23:30:00'),
        celestialObjectId: object.id,
        catalogObject: object,
      );

      expect(
        outbox.created?.payload,
        containsPair('observation_date', '2026-08-17'),
      );
      expect(
        outbox.created?.payload,
        containsPair('canonical_target_id', 'M31'),
      );
      expect(
        outbox.created?.payload,
        containsPair('target_display_name', 'Andromeda Galaxy'),
      );
    },
  );

  test(
    'cross-catalog selection reuses its effective primary identity',
    () async {
      final outbox = _CapturingOutbox();
      final service = PhotoRegistrationService(
        photoService: _FakePhotoService(),
        geocodingService: GeocodingService(),
        apiKeyService: ApiKeyService(),
        exifService: ExifService(),
        shootingRecordRepository: _MemoryRecords(),
        catalogRepository: _MemoryCatalog(),
        syncOutboxRepository: outbox,
      );
      const alias = CatalogObject(
        id: 'NGC224',
        number: 224,
        catalog: CatalogType.ngc,
        name: 'Andromeda Galaxy',
        type: 'Galaxy',
        constellation: 'Andromeda',
        ra: '',
        dec: '',
        magnitude: '',
        isPrimaryCatalog: false,
        primaryCatalogId: 'M31',
      );

      await service.registerPhotoRecord(
        payload: _payload(exifDate: ''),
        confirmed: const ConfirmedMetadata(),
        celestialObjectId: alias.id,
        catalogObject: alias,
      );

      expect(
        outbox.created?.payload,
        containsPair('canonical_target_id', 'M31'),
      );
      expect(outbox.created?.payload, isNot(contains('observation_date')));
    },
  );

  test(
    'production projection marks M54 captured after ShootingRecord save',
    () async {
      const object = CatalogObject(
        id: 'M54',
        number: 54,
        catalog: CatalogType.messier,
        name: 'M54',
        type: 'Globular Cluster',
        constellation: 'Sagittarius',
        ra: '',
        dec: '',
        magnitude: '7.6',
      );
      final records = _MemoryRecords();
      final catalog = _MemoryCatalog([object]);
      final projection = CatalogCaptureProjectionService(
        catalogRepository: catalog,
        localRecords: records,
        galleryRepository: _EmptyGallery(),
      );
      final service = PhotoRegistrationService(
        photoService: _FakePhotoService(),
        geocodingService: GeocodingService(),
        apiKeyService: ApiKeyService(),
        exifService: ExifService(),
        shootingRecordRepository: records,
        catalogRepository: catalog,
        syncOutboxRepository: _CapturingOutbox(),
        catalogCaptureProjection: projection,
      );

      await service.registerPhotoRecord(
        payload: _payload(exifDate: '2026-08-18T22:00:00'),
        confirmed: const ConfirmedMetadata(capturedAt: '2026-08-18T22:00:00'),
        celestialObjectId: object.id,
        catalogObject: object,
      );

      expect(records.records, hasLength(1));
      expect((await catalog.getById('M54'))?.captured, isTrue);
      expect((await catalog.getById('M54'))?.capturedDate, '2026-08-18');
    },
  );
}

PhotoRegistrationPayload _payload({required String exifDate}) =>
    PhotoRegistrationPayload(
      photoId: 'photo-id',
      localPath: 'photo.jpg',
      originalFilename: 'photo.jpg',
      exifInfo: ExifInfo(
        filename: 'photo.jpg',
        size: '',
        date: exifDate,
        equipment: '',
        focal: '',
        fstop: '',
        exposure: '',
        iso: '',
        resolution: '',
      ),
      metadata: const PhotoMetadata(),
    );

class _FakePhotoService implements PhotoService {
  @override
  Future<void> savePickResult(PhotoPickResult result) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryRecords implements ShootingRecordRepository {
  final records = <ShootingRecord>[];

  @override
  Future<List<ShootingRecord>> getAll() async => List.of(records);

  @override
  Future<List<ShootingRecord>> getByCelestialObjectId(String id) async =>
      records.where((record) => record.celestialObjectId == id).toList();

  @override
  Future<void> save(ShootingRecord record) async => records.add(record);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryCatalog implements CatalogRepository {
  _MemoryCatalog([this.objects = const []]);

  List<CatalogObject> objects;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => objects;

  @override
  Future<CatalogObject?> getById(String id) async {
    for (final object in objects) {
      if (object.id == id) return object;
    }
    return null;
  }

  @override
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {
    objects = [
      for (final object in objects)
        if (object.id == id)
          CatalogObject(
            id: object.id,
            number: object.number,
            catalog: object.catalog,
            name: object.name,
            type: object.type,
            constellation: object.constellation,
            ra: object.ra,
            dec: object.dec,
            magnitude: object.magnitude,
            captured: captured,
            capturedDate: capturedDate,
          )
        else
          object,
    ];
  }

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyGallery implements GalleryRepository {
  @override
  Future<GallerySnapshot> getSnapshot({bool forceRefresh = false}) async =>
      const GallerySnapshot(
        items: [],
        source: GallerySnapshotSource.none,
        backendEnabled: false,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CapturingOutbox implements SyncOutboxRepository {
  SyncOutboxItem? created;

  @override
  Future<void> create(SyncOutboxItem item) async => created = item;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
