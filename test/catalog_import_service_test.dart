import 'dart:convert';
import 'dart:io';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/data/database/app_database.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getTemporaryDirectory') {
            return Directory.systemTemp.path;
          }
          return null;
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  late Database db;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: DatabaseConstants.databaseVersion,
      onCreate: AppDatabase.createForTest,
    );
  });

  tearDown(() => db.close());

  test('current version with an empty catalog runs seed import', () async {
    final prefs = await _preferencesWithVersion(
      DatabaseConstants.catalogDataVersion,
    );
    var importCalls = 0;

    final imported = await CatalogImportService.importAllIfNeededForTesting(
      db: db,
      prefs: prefs,
      importPipeline: (database) async {
        importCalls++;
        await _insertCatalogObject(database, id: 'M42');
      },
    );

    expect(imported, isTrue);
    expect(importCalls, 1);
    expect(
      await CatalogImportService.hasUsableCatalogDataForTesting(db),
      isTrue,
    );
    expect(
      prefs.getInt('catalog_data_version'),
      DatabaseConstants.catalogDataVersion,
    );
  });

  test('current version with usable catalog data skips import', () async {
    final prefs = await _preferencesWithVersion(
      DatabaseConstants.catalogDataVersion,
    );
    await _insertCatalogObject(db, id: 'M42');
    var importCalls = 0;

    final imported = await CatalogImportService.importAllIfNeededForTesting(
      db: db,
      prefs: prefs,
      importPipeline: (_) async {
        importCalls++;
      },
    );

    expect(imported, isFalse);
    expect(importCalls, 0);
  });

  test('version mismatch keeps the existing import behavior', () async {
    final prefs = await _preferencesWithVersion(
      DatabaseConstants.catalogDataVersion - 1,
    );
    await _insertCatalogObject(db, id: 'M42');
    var importCalls = 0;

    final imported = await CatalogImportService.importAllIfNeededForTesting(
      db: db,
      prefs: prefs,
      importPipeline: (_) async {
        importCalls++;
      },
    );

    expect(imported, isTrue);
    expect(importCalls, 1);
    expect(
      prefs.getInt('catalog_data_version'),
      DatabaseConstants.catalogDataVersion,
    );
  });

  test(
    'bundled seed restores the full catalog and preserves user data',
    () async {
      final prefs = await _preferencesWithVersion(
        DatabaseConstants.catalogDataVersion - 1,
      );
      await prefs.setString('unrelated_user_setting', 'keep');
      await _insertCatalogObject(
        db,
        id: 'M42',
        captured: true,
        capturedDate: '2026-10-20T00:00:00Z',
        photoUri: '/user/m42.jpg',
        memo: '사용자 메모',
      );
      await db.insert(DatabaseConstants.tableShootingRecords, {
        DatabaseConstants.colId: 'record-m42',
        DatabaseConstants.colCelestialObjectId: 'M42',
        DatabaseConstants.colCapturedAt: '2026-10-20T00:00:00Z',
        DatabaseConstants.colPhotoUri: '/user/m42.jpg',
        DatabaseConstants.colMemo: '촬영 기록 메모',
        DatabaseConstants.colCreatedAt: '2026-10-20T00:00:00Z',
      });
      await db.insert(DatabaseConstants.tableEquipment, {
        DatabaseConstants.colId: 'equipment-1',
        DatabaseConstants.colName: '사용자 장비',
        DatabaseConstants.colEquipmentKind: 'telescope',
        DatabaseConstants.colEquipmentPurpose: 'imaging',
      });
      await db.insert(DatabaseConstants.tableObservationSites, {
        DatabaseConstants.colId: 'site-1',
        DatabaseConstants.colName: '사용자 관측지',
        DatabaseConstants.colLatitude: 37.5,
        DatabaseConstants.colLongitude: 127.0,
        DatabaseConstants.colCreatedAt: '2026-10-20T00:00:00Z',
        'updated_at': '2026-10-20T00:00:00Z',
      });
      final favoritePayload = jsonEncode([
        {
          'catalog_object_id': 'M42',
          'created_at': '2026-10-20T00:00:00Z',
          'updated_at': '2026-10-20T00:00:00Z',
        },
      ]);
      await db.insert(DatabaseConstants.tableGalleryCache, {
        'cache_key': 'catalog:favorites:v1',
        'payload_json': favoritePayload,
        'cached_at': '2026-10-20T00:00:00Z',
      });
      await db.insert(DatabaseConstants.tableSyncOutbox, {
        'operation_id': 'operation-1',
        'operation_type': 'PHOTO_UPLOAD_AND_RECORD',
        'state': 'WAITING',
        'retry_count': 0,
        'created_at': '2026-10-20T00:00:00Z',
        'updated_at': '2026-10-20T00:00:00Z',
      });

      final imported = await CatalogImportService.importAllIfNeededForTesting(
        db: db,
        prefs: prefs,
      );

      expect(imported, isTrue);
      expect(await _count(db, DatabaseConstants.tableCelestialObjects), 13562);
      expect(
        await _count(
          db,
          DatabaseConstants.tableCelestialObjects,
          where: '${DatabaseConstants.colIsPrimaryCatalog} = 1',
        ),
        13491,
      );

      final m42 = (await db.query(
        DatabaseConstants.tableCelestialObjects,
        where: '${DatabaseConstants.colId} = ?',
        whereArgs: ['M42'],
      )).single;
      expect(m42[DatabaseConstants.colCaptured], 1);
      expect(m42[DatabaseConstants.colCapturedDate], '2026-10-20T00:00:00Z');
      expect(m42[DatabaseConstants.colPhotoUri], '/user/m42.jpg');
      expect(m42[DatabaseConstants.colMemo], '사용자 메모');

      final shootingRecord = (await db.query(
        DatabaseConstants.tableShootingRecords,
      )).single;
      expect(shootingRecord[DatabaseConstants.colId], 'record-m42');
      expect(shootingRecord[DatabaseConstants.colMemo], '촬영 기록 메모');
      expect(await _count(db, DatabaseConstants.tableEquipment), 1);
      expect(await _count(db, DatabaseConstants.tableObservationSites), 1);
      expect(await _count(db, DatabaseConstants.tableSyncOutbox), 1);
      final favoriteCache = (await db.query(
        DatabaseConstants.tableGalleryCache,
        where: 'cache_key = ?',
        whereArgs: ['catalog:favorites:v1'],
      )).single;
      expect(favoriteCache['payload_json'], favoritePayload);
      expect(prefs.getString('unrelated_user_setting'), 'keep');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<SharedPreferences> _preferencesWithVersion(int version) async {
  SharedPreferences.setMockInitialValues({'catalog_data_version': version});
  return SharedPreferences.getInstance();
}

Future<void> _insertCatalogObject(
  Database db, {
  required String id,
  bool captured = false,
  String? capturedDate,
  String? photoUri,
  String memo = '',
}) => db.insert(
  DatabaseConstants.tableCelestialObjects,
  CatalogObject(
    id: id,
    number: 42,
    catalog: CatalogType.messier,
    name: '오리온 대성운',
    type: '발광성운',
    constellation: '오리온자리',
    ra: '05h 35m 17.3s',
    dec: '-05° 23′ 28″',
    magnitude: '4.0',
    captured: captured,
    capturedDate: capturedDate,
    photoUri: photoUri,
    memo: memo,
  ).toMap(),
);

Future<int> _count(Database db, String table, {String? where}) async =>
    Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM $table${where == null ? '' : ' WHERE $where'}',
      ),
    ) ??
    0;
