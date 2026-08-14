import 'dart:convert';
import 'dart:io';

import 'package:astro_journal/core/constants/database_constants.dart';
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
