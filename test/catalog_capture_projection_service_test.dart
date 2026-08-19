import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/datasources/gallery_record_link_datasource.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/gallery_item.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/gallery_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/services/catalog_capture_projection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogCaptureProjectionService', () {
    test(
      'local M54 registration is projected and survives reconstruction',
      () async {
        final harness = _Harness();
        harness.local.records.add(_record('local-1', 'M54', 'photo-1.jpg'));

        final first = await harness.service.reconcileObject('M54');
        final restarted = harness.rebuildService();
        final afterRestart = await restarted.reconcileAll();

        expect(first.captured, isTrue);
        expect(first.photoCount, 1);
        expect(first.capturedDate, '2026-08-18');
        expect(harness.catalog.captured('M54'), isTrue);
        expect(afterRestart.single.photoCount, 1);
      },
    );

    test(
      'cross-catalog NGC 6715 identity updates canonical M54 only',
      () async {
        final harness = _Harness();
        harness.local.records.add(_record('local-1', 'NGC6715', 'photo-1.jpg'));

        final result = await harness.service.reconcileObject('NGC6715');

        expect(result.catalogObjectId, 'M54');
        expect(harness.catalog.captured('M54'), isTrue);
        expect(harness.catalog.captured('NGC6715'), isFalse);
      },
    );

    test(
      'remote-only record repairs captured state during startup reconciliation',
      () async {
        final harness = _Harness();
        harness.gallery.items.add(_gallery('remote-1', 'file-1', 'M54'));

        final results = await harness.service.reconcileAll();

        expect(results.single.captured, isTrue);
        expect(results.single.localCount, 0);
        expect(results.single.remoteCount, 1);
        expect(harness.catalog.captured('M54'), isTrue);
      },
    );

    test(
      'linked local and remote copies are deduplicated as one photo',
      () async {
        final harness = _Harness(links: {'remote-1': 'local-1'});
        harness.local.records.add(_record('local-1', 'M54', 'same.jpg'));
        harness.gallery.items.add(_gallery('remote-1', 'file-1', 'M54'));

        final result = await harness.service.reconcileObject('M54');

        expect(result.photoCount, 1);
        expect(result.localCount, 1);
        expect(result.remoteCount, 1);
        expect(result.deduplicatedCount, 1);
      },
    );

    test(
      'deleting one of two photos keeps captured; deleting last clears date',
      () async {
        final harness = _Harness();
        harness.local.records
          ..add(_record('local-1', 'M54', 'one.jpg'))
          ..add(
            _record(
              'local-2',
              'M54',
              'two.jpg',
              capturedAt: DateTime(2026, 8, 19, 2),
            ),
          );

        expect((await harness.service.reconcileObject('M54')).photoCount, 2);
        harness.local.records.removeWhere((item) => item.id == 'local-1');
        expect((await harness.service.reconcileObject('M54')).photoCount, 1);
        expect(harness.catalog.captured('M54'), isTrue);

        harness.local.records.clear();
        final empty = await harness.service.reconcileObject('M54');

        expect(empty.captured, isFalse);
        expect(empty.capturedDate, isNull);
        expect(harness.catalog.captured('M54'), isFalse);
        expect(harness.catalog.capturedDate('M54'), isNull);
      },
    );

    test(
      'local zero and remote one remains captured until remote tombstone',
      () async {
        final harness = _Harness();
        harness.gallery.items.add(_gallery('remote-1', 'file-1', 'M54'));

        expect((await harness.service.reconcileObject('M54')).captured, isTrue);
        harness.gallery.items.clear();
        final deleted = await harness.service.reconcileObject('M54');

        expect(deleted.captured, isFalse);
        expect(harness.catalog.captured('M54'), isFalse);
      },
    );

    test('zero-row catalog update is detected and retained as dirty', () async {
      final harness = _Harness();
      harness.local.records.add(_record('local-1', 'M54', 'photo.jpg'));
      harness.catalog.returnZeroRows = true;

      await expectLater(
        harness.service.reconcileObject('M54'),
        throwsA(isA<CatalogCaptureProjectionException>()),
      );

      expect(harness.service.dirtyIdentities, contains('M54'));
    });

    test(
      'concurrent reconciliation calls are serialized and remain idempotent',
      () async {
        final harness = _Harness();
        harness.local.records.add(_record('local-1', 'M54', 'photo.jpg'));

        final results = await Future.wait([
          harness.service.reconcileObject('M54'),
          harness.service.reconcileObject('M54'),
        ]);

        expect(results, everyElement(isA<CatalogCaptureProjection>()));
        expect(results.last.photoCount, 1);
        expect(harness.catalog.successfulWrites, 1);
      },
    );

    test(
      '13k catalog rows and 1k active records reconcile by distinct target',
      () async {
        final harness = _Harness();
        for (var index = 0; index < 13000; index++) {
          harness.catalog.objects.add(
            _catalog('IC${100000 + index}', 100000 + index, CatalogType.ic),
          );
        }
        for (var index = 0; index < 1000; index++) {
          harness.local.records.add(
            _record('local-$index', 'M54', 'photo-$index.jpg'),
          );
        }

        final stopwatch = Stopwatch()..start();
        final result = await harness.service.reconcileAll();
        stopwatch.stop();

        expect(result.single.photoCount, 1000);
        expect(harness.catalog.successfulWrites, 1);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });
}

class _Harness {
  _Harness({Map<String, String> links = const {}})
    : catalog = _FakeCatalogRepository(),
      local = _FakeShootingRecordRepository(),
      gallery = _FakeGalleryRepository(),
      links = _FakeLinks(links) {
    service = rebuildService();
  }

  final _FakeCatalogRepository catalog;
  final _FakeShootingRecordRepository local;
  final _FakeGalleryRepository gallery;
  final _FakeLinks links;
  late CatalogCaptureProjectionService service;

  CatalogCaptureProjectionService rebuildService() =>
      CatalogCaptureProjectionService(
        catalogRepository: catalog,
        localRecords: local,
        galleryRepository: gallery,
        recordLinks: links,
      );
}

class _FakeCatalogRepository
    implements CatalogRepository, CatalogCaptureProjectionWriter {
  _FakeCatalogRepository()
    : objects = [
        _catalog('M54', 54, CatalogType.messier),
        _catalog(
          'NGC6715',
          6715,
          CatalogType.ngc,
          primary: false,
          primaryId: 'M54',
        ),
      ];

  final List<CatalogObject> objects;
  final Map<String, bool> _captured = {};
  final Map<String, String?> _capturedDate = {};
  bool returnZeroRows = false;
  int successfulWrites = 0;

  bool captured(String id) => _captured[id] ?? false;
  String? capturedDate(String id) => _capturedDate[id];

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => [
    for (final object in objects) _withProjection(object),
  ];

  @override
  Future<CatalogObject?> getById(String id) async {
    for (final object in objects) {
      if (object.id == id) return _withProjection(object);
    }
    return null;
  }

  @override
  Future<int> updateCaptureProjection(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {
    if (returnZeroRows || !objects.any((item) => item.id == id)) return 0;
    _captured[id] = captured;
    _capturedDate[id] = capturedDate;
    successfulWrites++;
    return 1;
  }

  @override
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {
    await updateCaptureProjection(
      id,
      captured: captured,
      capturedDate: capturedDate,
    );
  }

  CatalogObject _withProjection(CatalogObject object) => CatalogObject(
    id: object.id,
    number: object.number,
    catalog: object.catalog,
    name: object.name,
    type: object.type,
    constellation: object.constellation,
    ra: object.ra,
    dec: object.dec,
    magnitude: object.magnitude,
    aliases: object.aliases,
    crossCatalogRefs: object.crossCatalogRefs,
    captured: captured(object.id),
    capturedDate: capturedDate(object.id),
    isPrimaryCatalog: object.isPrimaryCatalog,
    primaryCatalogId: object.primaryCatalogId,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShootingRecordRepository implements ShootingRecordRepository {
  final List<ShootingRecord> records = [];

  @override
  Future<List<ShootingRecord>> getAll() async => List.of(records);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGalleryRepository implements GalleryRepository {
  final List<GalleryItem> items = [];

  @override
  Future<GallerySnapshot> getSnapshot({bool forceRefresh = false}) async =>
      GallerySnapshot(
        items: List.of(items),
        source: GallerySnapshotSource.cache,
        backendEnabled: true,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLinks implements GalleryRecordLinkDataSource {
  const _FakeLinks(this.links);

  final Map<String, String> links;

  @override
  Future<Map<String, String>> localIdsByBackendRecordId() async => links;
}

CatalogObject _catalog(
  String id,
  int number,
  CatalogType type, {
  bool primary = true,
  String? primaryId,
}) => CatalogObject(
  id: id,
  number: number,
  catalog: type,
  name: id,
  type: 'Globular Cluster',
  constellation: 'Sgr',
  ra: '18:55:03',
  dec: '-30:28:42',
  magnitude: '7.6',
  crossCatalogRefs: id == 'M54' ? const ['NGC 6715'] : const ['M54'],
  isPrimaryCatalog: primary,
  primaryCatalogId: primaryId,
);

ShootingRecord _record(
  String id,
  String catalogObjectId,
  String photoUri, {
  DateTime? capturedAt,
}) => ShootingRecord(
  id: id,
  celestialObjectId: catalogObjectId,
  capturedAt: capturedAt ?? DateTime(2026, 8, 18, 1),
  photoUri: photoUri,
  createdAt: DateTime(2026, 8, 18, 2),
);

GalleryItem _gallery(String recordId, String fileId, String catalogObjectId) =>
    GalleryItem(
      backendRecordId: recordId,
      revision: 1,
      catalogObjectId: catalogObjectId,
      capturedAt: DateTime(2026, 8, 18, 1),
      favorite: false,
      representative: false,
      backendFileId: fileId,
      thumbnailUrl: '/thumbnail',
      previewUrl: '/preview',
      originalUrl: '/original',
    );
