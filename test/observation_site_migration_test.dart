import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/legacy_equipment_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v31 favorites migrate through v34 without data loss', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await createLegacyEquipmentTables(db, seedRows: true);
    await db.execute('''
      CREATE TABLE observation_site_favorites (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        bortle INTEGER,
        sqm REAL,
        brightness_grade TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.insert('observation_site_favorites', {
      'id': 'legacy-site',
      'name': 'Legacy Site',
      'latitude': 37.5,
      'longitude': 127.0,
      'bortle': 8,
      'sqm': 18.2,
      'brightness_grade': 'urban',
      'created_at': '2026-08-18T12:00:00.000',
    });

    await AppDatabase.migrateForTest(db, 31, 34);

    final rows = await db.query(DatabaseConstants.tableObservationSites);
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row['id'], 'legacy-site');
    expect(row['name'], 'Legacy Site');
    expect(row['latitude'], 37.5);
    expect(row['longitude'], 127.0);
    expect(row['bortle'], 8);
    expect(row['sqm'], 18.2);
    expect(row['brightness_grade'], 'urban');
    expect(row['is_favorite'], 1);
    expect(row['tracking_mode'], 'altAz');
    expect(row['default_min_altitude'], 20.0);
    expect(row['default_max_altitude'], isNull);
    expect(row['deleted_at'], isNull);
    expect(
      await db.query(DatabaseConstants.tableObservationSiteFavorites),
      hasLength(1),
    );
    expect(await db.query(DatabaseConstants.tableEquipment), hasLength(1));
    expect(await db.query(DatabaseConstants.tableEyepieces), hasLength(1));
    expect(DatabaseConstants.databaseVersion, 34);
  });

  test('fresh v34 schema contains site and equipment sync tables', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await AppDatabase.createForTest(db, 34);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(names, contains(DatabaseConstants.tableObservationSites));
    expect(
      names,
      contains(DatabaseConstants.tableObservationSiteHorizonPoints),
    );
    expect(
      names,
      contains(DatabaseConstants.tableObservationSiteBlockedAzimuthRanges),
    );
    expect(names, contains(DatabaseConstants.tableObservationSiteSyncState));
    expect(names, contains(DatabaseConstants.tableObservationSiteSyncOutbox));
    expect(names, contains(DatabaseConstants.tableEquipmentSyncState));
    expect(names, contains(DatabaseConstants.tableEquipmentSyncOutbox));
    final equipmentColumns = await db.rawQuery('PRAGMA table_info(equipment)');
    final columnNames = equipmentColumns.map((row) => row['name']).toSet();
    expect(
      columnNames,
      contains(DatabaseConstants.colAzExposureCapabilityJson),
    );
    expect(
      columnNames,
      contains(DatabaseConstants.colEqExposureCapabilityJson),
    );
  });

  test('v32 to v34 adds sync tables without replacing site rows', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await createLegacyEquipmentTables(db, seedRows: true);
    await _createV32ObservationSiteTables(db);
    await db.insert(DatabaseConstants.tableObservationSites, {
      'id': 'site-before-v33',
      'name': 'Existing site',
      'latitude': 37.5,
      'longitude': 127.0,
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': '2026-09-01T00:00:00Z',
    });

    await AppDatabase.migrateForTest(db, 32, 34);

    expect(
      await db.query(DatabaseConstants.tableObservationSites),
      hasLength(1),
    );
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(names, contains(DatabaseConstants.tableObservationSiteSyncState));
    expect(names, contains(DatabaseConstants.tableObservationSiteSyncOutbox));
    expect(names, contains(DatabaseConstants.tableEquipmentSyncState));
    expect(names, contains(DatabaseConstants.tableEquipmentSyncOutbox));
    expect(await db.query(DatabaseConstants.tableEquipment), hasLength(1));
    expect(await db.query(DatabaseConstants.tableEyepieces), hasLength(1));
    final equipmentColumns = await db.rawQuery('PRAGMA table_info(equipment)');
    final columnNames = equipmentColumns.map((row) => row['name']).toSet();
    expect(
      columnNames,
      contains(DatabaseConstants.colAzExposureCapabilityJson),
    );
    expect(
      columnNames,
      contains(DatabaseConstants.colEqExposureCapabilityJson),
    );
  });

  test(
    'v33 to v34 preserves equipment and adds capability sync schema',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await createLegacyEquipmentTables(db, seedRows: true);

      await AppDatabase.migrateForTest(db, 33, 34);

      expect(await db.query('equipment'), hasLength(1));
      expect(await db.query('eyepieces'), hasLength(1));
      expect(
        await db.query(DatabaseConstants.tableEquipmentSyncState),
        isEmpty,
      );
      expect(
        await db.query(DatabaseConstants.tableEquipmentSyncOutbox),
        isEmpty,
      );
    },
  );
}

Future<void> _createV32ObservationSiteTables(Database db) async {
  await db.execute('''
    CREATE TABLE observation_sites (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      address TEXT,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      bortle INTEGER,
      sqm REAL,
      brightness_grade TEXT,
      is_favorite INTEGER NOT NULL DEFAULT 1,
      tracking_mode TEXT NOT NULL DEFAULT 'altAz',
      default_equipment_id TEXT,
      default_min_altitude REAL NOT NULL DEFAULT 20,
      default_max_altitude REAL,
      preferred_start TEXT,
      preferred_end TEXT,
      memo TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      last_used_at TEXT,
      deleted_at TEXT,
      FOREIGN KEY (default_equipment_id)
        REFERENCES equipment (id) ON DELETE SET NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE observation_site_horizon_points (
      id TEXT PRIMARY KEY,
      observation_site_id TEXT NOT NULL,
      azimuth REAL NOT NULL CHECK (azimuth >= 0 AND azimuth < 360),
      min_altitude REAL NOT NULL CHECK (
        min_altitude >= -90 AND min_altitude <= 90
      ),
      max_altitude REAL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      source TEXT NOT NULL DEFAULT 'manual',
      CHECK (
        max_altitude IS NULL OR
        (max_altitude >= min_altitude AND max_altitude <= 90)
      ),
      FOREIGN KEY (observation_site_id)
        REFERENCES observation_sites (id) ON DELETE CASCADE,
      UNIQUE (observation_site_id, azimuth)
    )
  ''');
  await db.execute('''
    CREATE TABLE observation_site_blocked_azimuth_ranges (
      id TEXT PRIMARY KEY,
      observation_site_id TEXT NOT NULL,
      start_azimuth REAL NOT NULL CHECK (
        start_azimuth >= 0 AND start_azimuth < 360
      ),
      end_azimuth REAL NOT NULL CHECK (
        end_azimuth >= 0 AND end_azimuth < 360
      ),
      reason TEXT,
      source TEXT NOT NULL DEFAULT 'manual',
      FOREIGN KEY (observation_site_id)
        REFERENCES observation_sites (id) ON DELETE CASCADE
    )
  ''');
}
