import 'dart:convert';
import 'dart:io';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_import_service.dart';
import 'package:astro_journal/services/catalog_seed_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('authoritative Caldwell source is complete and unambiguous', () {
    final root =
        jsonDecode(
              File(
                'tools/catalog_data/caldwell_identity.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final mapping = root['mapping'] as Map<String, dynamic>;

    expect(mapping, hasLength(109));
    expect(mapping.keys.toSet(), {
      for (var number = 1; number <= 109; number++) '$number',
    });
    expect(mapping['57'], 'NGC6822');
    expect(mapping['63'], 'NGC7293');
  });

  test('IAU constellation source contains 88 distinct mappings', () {
    final mapping =
        jsonDecode(
              File(
                'tools/catalog_data/constellations_ko.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    expect(mapping, hasLength(88));
    expect(mapping.values.toSet(), hasLength(88));
    expect(mapping['Lib'], '천칭자리');
    expect(mapping['Vir'], '처녀자리');
  });

  test('catalog refresh replaces aliases but preserves user-owned fields', () {
    final existing = <String, dynamic>{
      DatabaseConstants.colCaptured: 1,
      DatabaseConstants.colCapturedDate: '2026-08-14T00:00:00Z',
      DatabaseConstants.colPhotoUri: '/user/photo.jpg',
      DatabaseConstants.colMemo: '사용자 메모',
      DatabaseConstants.colExifJson: '{"camera":"user"}',
      DatabaseConstants.colAliasesJson: jsonEncode(['C63', 'Helix Nebula']),
      DatabaseConstants.colCrossCatalogRefsJson: jsonEncode(['NGC7293']),
    };
    final seed = <String, dynamic>{
      DatabaseConstants.colName: '바너드 은하',
      DatabaseConstants.colObjectType: '은하',
      DatabaseConstants.colMag: '10.05',
      DatabaseConstants.colAngularSize: "17.38' × 16.75'",
      DatabaseConstants.colMajorAxis: 17.38,
      DatabaseConstants.colMinorAxis: 16.75,
      DatabaseConstants.colAliasesJson: jsonEncode(['C57', 'IC4895']),
      DatabaseConstants.colCrossCatalogRefsJson: jsonEncode(['C57', 'IC4895']),
    };

    final updates = CatalogSeedImportService.buildMetadataUpdateForTesting(
      existing,
      seed,
    );

    expect(jsonDecode(updates[DatabaseConstants.colAliasesJson] as String), [
      'C57',
      'IC4895',
    ]);
    expect(
      jsonDecode(updates[DatabaseConstants.colCrossCatalogRefsJson] as String),
      ['C57', 'IC4895'],
    );
    expect(updates[DatabaseConstants.colMag], '10.05');
    expect(updates[DatabaseConstants.colAngularSize], "17.38' × 16.75'");
    expect(updates[DatabaseConstants.colMajorAxis], 17.38);
    expect(updates[DatabaseConstants.colMinorAxis], 16.75);
    expect(updates, isNot(contains(DatabaseConstants.colCaptured)));
    expect(updates, isNot(contains(DatabaseConstants.colCapturedDate)));
    expect(updates, isNot(contains(DatabaseConstants.colPhotoUri)));
    expect(updates, isNot(contains(DatabaseConstants.colMemo)));
    expect(updates, isNot(contains(DatabaseConstants.colExifJson)));
  });

  test(
    'Solar refresh clears stale DSO metadata and preserves capture data',
    () {
      final existing = <String, dynamic>{
        DatabaseConstants.colCatalog: 'solar',
        DatabaseConstants.colCaptured: 1,
        DatabaseConstants.colCapturedDate: '2026-08-14T00:00:00Z',
        DatabaseConstants.colPhotoUri: '/user/uranus.jpg',
        DatabaseConstants.colMemo: '사용자 천왕성 기록',
        DatabaseConstants.colExifJson: '{"camera":"user"}',
        DatabaseConstants.colName: '천왕성',
        DatabaseConstants.colObjectType: '행성',
        DatabaseConstants.colAliasesJson: jsonEncode([
          'Uranus',
          'Lagoon Nebula',
        ]),
        DatabaseConstants.colCrossCatalogRefsJson: jsonEncode(['LBN 25']),
        DatabaseConstants.colTagsJson: jsonEncode(['발광성운']),
        DatabaseConstants.colSearchKeywords: 'Lagoon Nebula|LBN 25',
        DatabaseConstants.colMajorAxis: 45.0,
        DatabaseConstants.colMinorAxis: 30.0,
        DatabaseConstants.colPositionAngle: 90.0,
      };
      final seed = <String, dynamic>{
        DatabaseConstants.colCatalog: 'solar',
        DatabaseConstants.colName: '천왕성',
        DatabaseConstants.colCommonName: '천왕성',
        DatabaseConstants.colObjectType: '행성',
        DatabaseConstants.colType: '행성',
        DatabaseConstants.colConstellation: '-',
        DatabaseConstants.colRa: '-',
        DatabaseConstants.colDec: '-',
        DatabaseConstants.colAliasesJson: jsonEncode(['Uranus']),
        DatabaseConstants.colCrossCatalogRefsJson: null,
        DatabaseConstants.colTagsJson: jsonEncode(['태양계', '행성']),
        DatabaseConstants.colSearchKeywords: null,
        DatabaseConstants.colMajorAxis: null,
        DatabaseConstants.colMinorAxis: null,
        DatabaseConstants.colPositionAngle: null,
      };

      final updates = CatalogSeedImportService.buildMetadataUpdateForTesting(
        existing,
        seed,
      );

      expect(jsonDecode(updates[DatabaseConstants.colAliasesJson] as String), [
        'Uranus',
      ]);
      expect(updates[DatabaseConstants.colCrossCatalogRefsJson], isNull);
      expect(jsonDecode(updates[DatabaseConstants.colTagsJson] as String), [
        '태양계',
        '행성',
      ]);
      expect(updates[DatabaseConstants.colSearchKeywords], isNull);
      expect(updates[DatabaseConstants.colMajorAxis], isNull);
      expect(updates[DatabaseConstants.colMinorAxis], isNull);
      expect(updates[DatabaseConstants.colPositionAngle], isNull);
      expect(updates, isNot(contains(DatabaseConstants.colCaptured)));
      expect(updates, isNot(contains(DatabaseConstants.colCapturedDate)));
      expect(updates, isNot(contains(DatabaseConstants.colPhotoUri)));
      expect(updates, isNot(contains(DatabaseConstants.colMemo)));
      expect(updates, isNot(contains(DatabaseConstants.colExifJson)));
    },
  );

  test(
    'existing database receives corrected Solar rows without data loss',
    () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final corruptedUranus = CatalogObject(
        id: 'solar_8',
        number: 8,
        catalog: CatalogType.solar,
        name: '천왕성',
        commonName: '천왕성',
        type: '행성',
        objectType: '행성',
        constellation: '궁수자리',
        ra: '-',
        dec: '-',
        magnitude: '5.80',
        aliases: const ['Lagoon Nebula', 'LBN 25'],
        crossCatalogRefs: const ['LBN 25'],
        captured: true,
        capturedDate: '2026-08-14T00:00:00Z',
        photoUri: '/user/uranus.jpg',
        memo: '사용자 천왕성 기록',
      ).toMap();
      await db.insert(DatabaseConstants.tableCelestialObjects, corruptedUranus);
      await db.insert(DatabaseConstants.tableShootingRecords, {
        DatabaseConstants.colId: 'record-uranus',
        DatabaseConstants.colCelestialObjectId: 'solar_8',
        DatabaseConstants.colCapturedAt: '2026-08-14T00:00:00Z',
        DatabaseConstants.colPhotoUri: '/user/uranus.jpg',
        DatabaseConstants.colMemo: '사용자 천왕성 기록',
        DatabaseConstants.colCreatedAt: '2026-08-14T00:00:00Z',
      });

      final source =
          jsonDecode(File('assets/catalog/solar.json').readAsStringSync())
              as List<dynamic>;
      final seedRows = source
          .map(
            (item) => CatalogObject.fromJson(
              item as Map<String, dynamic>,
              CatalogType.solar,
            ).toMap(),
          )
          .toList(growable: false);
      await db.transaction(
        (txn) => CatalogSeedImportService.importRowsForTesting(txn, seedRows),
      );

      final solarRows = await db.query(
        DatabaseConstants.tableCelestialObjects,
        where: '${DatabaseConstants.colCatalog} = ?',
        whereArgs: [CatalogType.solar.value],
      );
      expect(solarRows, hasLength(14));
      final uranus = solarRows.singleWhere(
        (row) => row[DatabaseConstants.colId] == 'solar_8',
      );
      expect(uranus[DatabaseConstants.colName], '천왕성');
      expect(uranus[DatabaseConstants.colConstellation], '-');
      expect(jsonDecode(uranus[DatabaseConstants.colAliasesJson] as String), [
        'Uranus',
      ]);
      expect(uranus[DatabaseConstants.colCrossCatalogRefsJson], isNull);
      expect(uranus[DatabaseConstants.colCaptured], 1);
      expect(uranus[DatabaseConstants.colCapturedDate], '2026-08-14T00:00:00Z');
      expect(uranus[DatabaseConstants.colPhotoUri], '/user/uranus.jpg');
      expect(uranus[DatabaseConstants.colMemo], '사용자 천왕성 기록');

      final record = (await db.query(
        DatabaseConstants.tableShootingRecords,
      )).single;
      expect(record[DatabaseConstants.colCelestialObjectId], 'solar_8');
      expect(record[DatabaseConstants.colPhotoUri], '/user/uranus.jpg');
      expect(record[DatabaseConstants.colMemo], '사용자 천왕성 기록');
    },
  );

  test('explicit id remap keeps an existing shooting record linked', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    await db.insert(DatabaseConstants.tableShootingRecords, {
      DatabaseConstants.colId: 'record-1',
      DatabaseConstants.colCelestialObjectId: 'IC4895',
      DatabaseConstants.colCapturedAt: '2026-08-14T00:00:00Z',
      DatabaseConstants.colPhotoUri: '/user/photo.jpg',
      DatabaseConstants.colMemo: '보존할 메모',
      DatabaseConstants.colCreatedAt: '2026-08-14T00:00:00Z',
    });

    await CatalogImportService.remapShootingRecordsForTesting(db, {
      'IC4895': 'NGC6822',
    });

    final row = (await db.query(DatabaseConstants.tableShootingRecords)).single;
    expect(row[DatabaseConstants.colCelestialObjectId], 'NGC6822');
    expect(row[DatabaseConstants.colPhotoUri], '/user/photo.jpg');
    expect(row[DatabaseConstants.colMemo], '보존할 메모');
  });
}
