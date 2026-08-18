import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'v31 favorites migrate to v32 observation sites without data loss',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
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

      await AppDatabase.migrateForTest(db, 31, 32);

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
      expect(DatabaseConstants.databaseVersion, 32);
    },
  );

  test('fresh v32 schema contains canonical site and horizon tables', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await AppDatabase.createForTest(db, 32);

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
  });
}
