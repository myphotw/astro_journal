import 'dart:io';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/core/policies/catalog_deletion_policy.dart';
import 'package:astro_journal/data/database/app_database.dart';
import 'package:astro_journal/data/datasources/gallery_cache_local_datasource.dart';
import 'package:astro_journal/data/datasources/sync_checkpoint_datasource.dart';
import 'package:astro_journal/data/models/astrojournal_reset.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/photo.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/models/sync_outbox_item.dart';
import 'package:astro_journal/services/astrojournal_capture_reset_coordinator.dart';
import 'package:astro_journal/services/astrojournal_local_capture_reset_service.dart';
import 'package:astro_journal/services/tc_backend_astrojournal_reset_service.dart';
import 'package:astro_journal/services/tc_backend_sync_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Backend failure leaves every local row and file untouched', () async {
    final local = _FakeLocalReset();
    final api = _FakeResetApi()
      ..executeError = const AstroJournalResetException(
        type: AstroJournalResetErrorType.network,
        message: 'offline',
      );
    final coordinator = AstroJournalCaptureResetCoordinator(
      api,
      local,
      TcBackendSyncGate(),
    );

    await expectLater(
      coordinator.execute(),
      throwsA(isA<AstroJournalResetException>()),
    );
    expect(local.calls, 0);

    api.executeError = const AstroJournalResetException(
      type: AstroJournalResetErrorType.blocked,
      message: 'blocked',
      statusCode: 409,
    );
    await expectLater(
      coordinator.execute(),
      throwsA(isA<AstroJournalResetException>()),
    );
    expect(local.calls, 0);

    api.executeError = const AstroJournalResetException(
      type: AstroJournalResetErrorType.http,
      message: 'server error',
      statusCode: 500,
    );
    await expectLater(
      coordinator.execute(),
      throwsA(isA<AstroJournalResetException>()),
    );
    expect(local.calls, 0);
  });

  test('Preview failure never starts local cleanup', () async {
    final local = _FakeLocalReset();
    final api = _FakeResetApi()
      ..previewError = const AstroJournalResetException(
        type: AstroJournalResetErrorType.network,
        message: 'offline',
      );
    final coordinator = AstroJournalCaptureResetCoordinator(
      api,
      local,
      TcBackendSyncGate(),
    );

    await expectLater(
      coordinator.preview(),
      throwsA(isA<AstroJournalResetException>()),
    );
    expect(local.calls, 0);
  });

  test(
    'Backend success clears capture data and preserves setup data',
    () async {
      SharedPreferences.setMockInitialValues({'recommendation_setting': 7});
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: DatabaseConstants.databaseVersion,
        onCreate: AppDatabase.createForTest,
      );
      addTearDown(db.close);
      final managed = await Directory.systemTemp.createTemp(
        'astro-reset-managed-',
      );
      final external = await Directory.systemTemp.createTemp(
        'astro-reset-external-',
      );
      addTearDown(() => managed.delete(recursive: true));
      addTearDown(() => external.delete(recursive: true));
      final managedPhoto = File(
        '${managed.path}${Platform.pathSeparator}photo.jpg',
      );
      final externalOriginal = File(
        '${external.path}${Platform.pathSeparator}original.jpg',
      );
      await managedPhoto.writeAsString('managed');
      await externalOriginal.writeAsString('original');

      const custom = CatalogObject(
        id: '550e8400-e29b-41d4-a716-446655440000',
        number: 1,
        catalog: CatalogType.ngc,
        name: '사용자 대상',
        type: '성운',
        constellation: '테스트자리',
        ra: '',
        dec: '',
        magnitude: '-',
        captured: true,
        capturedDate: '2026-08-24',
        photoUri: 'photo.jpg',
        tags: [CatalogDeletionPolicy.userCreatedTag],
      );
      const builtIn = CatalogObject(
        id: 'M42',
        number: 42,
        catalog: CatalogType.messier,
        name: '오리온 성운',
        type: '성운',
        constellation: '오리온자리',
        ra: '',
        dec: '',
        magnitude: '4.0',
        captured: true,
        capturedDate: '2026-08-23',
        photoUri: 'm42.jpg',
      );
      await db.insert(DatabaseConstants.tableCelestialObjects, custom.toMap());
      await db.insert(DatabaseConstants.tableCelestialObjects, builtIn.toMap());
      await db.insert(
        DatabaseConstants.tableShootingRecords,
        ShootingRecord(
          id: 'record-1',
          celestialObjectId: custom.id,
          capturedAt: DateTime.utc(2026, 8, 24),
          photoUri: managedPhoto.path,
          createdAt: DateTime.utc(2026, 8, 24),
        ).toMap(),
      );
      await db.insert(
        DatabaseConstants.tablePhotos,
        Photo(
          id: 'photo-1',
          localPath: managedPhoto.path,
          createdAt: DateTime.utc(2026, 8, 24),
        ).toMap(),
      );
      await db.insert(
        DatabaseConstants.tableSyncOutbox,
        SyncOutboxItem(
          operationId: 'operation-1',
          localRecordId: 'record-1',
          payload: {'canonical_target_id': custom.id},
        ).toMap(),
      );
      await db.insert(DatabaseConstants.tableGalleryCache, {
        'cache_key': 'gallery:list',
        'payload_json': '{}',
        'cached_at': DateTime.utc(2026, 8, 24).toIso8601String(),
      });
      await db.insert(DatabaseConstants.tablePhotoObjects, {
        'id': 'object-1',
        'photo_id': 'record-1',
        'catalog_id': custom.id,
        'catalog_type': 'ngc',
        'display_name': custom.name,
        'ra': 1.0,
        'dec': 2.0,
        'angular_distance': 0.1,
        'confidence': 1.0,
        'is_primary_target': 1,
        'is_visible': 1,
        'created_at': DateTime.utc(2026, 8, 24).toIso8601String(),
      });
      await db.insert(DatabaseConstants.tableEquipment, {
        'id': 'equipment-1',
        'name': 'Seestar',
        'equipment_kind': 'telescope',
        'equipment_purpose': 'imaging',
      });
      await db.insert(DatabaseConstants.tableObservationSites, {
        'id': 'site-1',
        'name': '관측지',
        'latitude': 37.0,
        'longitude': 127.0,
        'tracking_mode': 'eq',
        'default_equipment_id': 'equipment-1',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'updated_at': DateTime.utc(2026).toIso8601String(),
      });
      await db.insert(DatabaseConstants.tableObservationSiteHorizonPoints, {
        'id': 'horizon-1',
        'observation_site_id': 'site-1',
        'azimuth': 0.0,
        'min_altitude': 20.0,
        'source': 'manual',
      });
      await db
          .insert(DatabaseConstants.tableObservationSiteBlockedAzimuthRanges, {
            'id': 'blocked-1',
            'observation_site_id': 'site-1',
            'start_azimuth': 10.0,
            'end_azimuth': 20.0,
            'source': 'manual',
          });

      var refreshCalls = 0;
      final localReset = AstroJournalLocalCaptureResetService(
        database: db,
        managedPhotosDirectory: () async => managed,
        onDataChanged: () async => refreshCalls++,
      );
      final api = _FakeResetApi();
      final coordinator = AstroJournalCaptureResetCoordinator(
        api,
        localReset,
        TcBackendSyncGate(),
      );

      await coordinator.execute();

      expect(await db.query(DatabaseConstants.tableShootingRecords), isEmpty);
      expect(await db.query(DatabaseConstants.tablePhotos), isEmpty);
      expect(await db.query(DatabaseConstants.tablePhotoObjects), isEmpty);
      expect(await db.query(DatabaseConstants.tableSyncOutbox), isEmpty);
      final cache = GalleryCacheLocalDataSource(database: db);
      expect(await cache.read('gallery:list'), isNull);
      final checkpoints = GalleryCacheSyncCheckpointDataSource(cache);
      expect(
        await checkpoints.readCursor(SyncCheckpointStreams.astroJournalChanges),
        '912',
      );

      final targetRows = await db.query(
        DatabaseConstants.tableCelestialObjects,
      );
      expect(targetRows, hasLength(2));
      final retained = CatalogObject.fromMap(
        targetRows.singleWhere((row) => row['id'] == custom.id),
      );
      expect(retained.name, custom.name);
      expect(retained.captured, isFalse);
      expect(retained.capturedDate, isNull);
      expect(retained.photoUri, isNull);
      final retainedBuiltIn = CatalogObject.fromMap(
        targetRows.singleWhere((row) => row['id'] == builtIn.id),
      );
      expect(retainedBuiltIn.name, builtIn.name);
      expect(retainedBuiltIn.captured, isFalse);

      expect(await db.query(DatabaseConstants.tableEquipment), hasLength(1));
      expect(
        await db.query(DatabaseConstants.tableObservationSites),
        hasLength(1),
      );
      expect(
        await db.query(DatabaseConstants.tableObservationSiteHorizonPoints),
        hasLength(1),
      );
      expect(
        await db.query(
          DatabaseConstants.tableObservationSiteBlockedAzimuthRanges,
        ),
        hasLength(1),
      );
      expect(
        (await SharedPreferences.getInstance()).getInt(
          'recommendation_setting',
        ),
        7,
      );
      expect(await managedPhoto.exists(), isFalse);
      expect(await externalOriginal.exists(), isTrue);
      expect(refreshCalls, 1);
      expect(api.executeCalls, 1);
    },
  );
}

class _FakeLocalReset implements AstroJournalLocalCaptureReset {
  int calls = 0;
  String? cursor;

  @override
  Future<void> clearCaptureData({String? resetEventCursor}) async {
    calls++;
    cursor = resetEventCursor;
  }
}

class _FakeResetApi implements AstroJournalResetApi {
  Object? previewError;
  Object? executeError;
  int executeCalls = 0;

  @override
  Future<AstroJournalResetPreview> preview() async {
    if (previewError case final error?) throw error;
    return _preview;
  }

  @override
  Future<AstroJournalResetResult> execute() async {
    executeCalls++;
    if (executeError case final error?) throw error;
    return _result;
  }
}

const _preview = AstroJournalResetPreview(
  observationRecordCount: 1,
  astroFileCount: 1,
  astroOnlyFileCount: 1,
  sharedFileCount: 0,
  plateSolveResultCount: 1,
  photoObjectCount: 1,
  uploadJobCount: 1,
  pendingUploadCount: 0,
  processingUploadCount: 0,
  processingVisionJobCount: 0,
  processingJobCount: 0,
  physicalOriginalDeleteCount: 1,
  physicalPreviewDeleteCount: 1,
  physicalThumbnailDeleteCount: 1,
  preservedSharedFileCount: 0,
  resetBlocked: false,
);

const _result = AstroJournalResetResult(
  resetCompleted: true,
  deletedObservationRecordCount: 1,
  removedAstroFileLinkCount: 1,
  tombstonedCommonFileCount: 1,
  preservedSharedFileCount: 0,
  deletedUploadJobCount: 1,
  deletedOriginalCount: 1,
  deletedPreviewCount: 1,
  deletedThumbnailCount: 1,
  deletedPlateSolveResultCount: 1,
  deletedPhotoObjectCount: 1,
  resetEventCursor: 912,
);
