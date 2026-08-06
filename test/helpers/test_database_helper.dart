import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:sqflite/sqflite.dart';

Future<Database> openTestDatabase() async {
  return openDatabase(
    inMemoryDatabasePath,
    version: DatabaseConstants.databaseVersion,
    onCreate: (db, version) async {
      await _createShootingRecordsTable(db);
      await _createCelestialObjectsTable(db);
      await _createIndexes(db);
    },
  );
}

Future<void> _createShootingRecordsTable(Database db) async {
  await db.execute('''
    CREATE TABLE ${DatabaseConstants.tableShootingRecords} (
      ${DatabaseConstants.colId} TEXT PRIMARY KEY,
      ${DatabaseConstants.colCelestialObjectId} TEXT NOT NULL,
      ${DatabaseConstants.colCapturedAt} TEXT NOT NULL,
      ${DatabaseConstants.colPhotoUri} TEXT,
      ${DatabaseConstants.colOriginalFilename} TEXT,
      ${DatabaseConstants.colMemo} TEXT NOT NULL DEFAULT '',
      ${DatabaseConstants.colLocation} TEXT,
      ${DatabaseConstants.colExifJson} TEXT,
      ${DatabaseConstants.colMetadataJson} TEXT,
      ${DatabaseConstants.colCreatedAt} TEXT NOT NULL,
      ${DatabaseConstants.colIsRepresentative} INTEGER NOT NULL DEFAULT 0,
      ${DatabaseConstants.colIsFavorite} INTEGER NOT NULL DEFAULT 0,
      ${DatabaseConstants.colPlateSolveJson} TEXT,
      ${DatabaseConstants.colDetectMethod} TEXT,
      ${DatabaseConstants.colAnalysisStatus} TEXT NOT NULL DEFAULT 'COMPLETED'
    )
  ''');
}

Future<void> _createCelestialObjectsTable(Database db) async {
  await db.execute('''
    CREATE TABLE ${DatabaseConstants.tableCelestialObjects} (
      ${DatabaseConstants.colId} TEXT PRIMARY KEY,
      ${DatabaseConstants.colNum} INTEGER NOT NULL,
      ${DatabaseConstants.colCatalog} TEXT NOT NULL,
      ${DatabaseConstants.colName} TEXT NOT NULL,
      ${DatabaseConstants.colType} TEXT NOT NULL,
      ${DatabaseConstants.colConstellation} TEXT NOT NULL,
      ${DatabaseConstants.colRa} TEXT NOT NULL,
      ${DatabaseConstants.colDec} TEXT NOT NULL,
      ${DatabaseConstants.colMag} TEXT NOT NULL,
      ${DatabaseConstants.colCaptured} INTEGER NOT NULL DEFAULT 0,
      ${DatabaseConstants.colCapturedDate} TEXT,
      ${DatabaseConstants.colPhotoUri} TEXT,
      ${DatabaseConstants.colMemo} TEXT NOT NULL DEFAULT '',
      ${DatabaseConstants.colExifJson} TEXT,
      ${DatabaseConstants.colAliasesJson} TEXT,
      ${DatabaseConstants.colCrossCatalogRefsJson} TEXT,
      ${DatabaseConstants.colCommonName} TEXT,
      ${DatabaseConstants.colObjectType} TEXT,
      ${DatabaseConstants.colSeestarSupported} INTEGER NOT NULL DEFAULT 0,
      ${DatabaseConstants.colSuffix} TEXT,
      ${DatabaseConstants.colTagsJson} TEXT,
      ${DatabaseConstants.colPeakMonth} INTEGER,
      ${DatabaseConstants.colBestSeason} TEXT,
      ${DatabaseConstants.colAngularSize} TEXT,
      ${DatabaseConstants.colDistanceLy} REAL,
      ${DatabaseConstants.colDescription} TEXT,
      ${DatabaseConstants.colSearchKeywords} TEXT,
      ${DatabaseConstants.colMajorAxis} REAL,
      ${DatabaseConstants.colMinorAxis} REAL,
      ${DatabaseConstants.colPositionAngle} REAL,
      ${DatabaseConstants.colDataSource} TEXT,
      ${DatabaseConstants.colIsFeatured} INTEGER NOT NULL DEFAULT 0,
      ${DatabaseConstants.colDisplayPriority} INTEGER NOT NULL DEFAULT ${DatabaseConstants.defaultDisplayPriority},
      ${DatabaseConstants.colIsPrimaryCatalog} INTEGER NOT NULL DEFAULT 1,
      ${DatabaseConstants.colPrimaryCatalogId} TEXT
    )
  ''');
}

Future<void> _createIndexes(Database db) async {
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_shooting_records_object_id
      ON ${DatabaseConstants.tableShootingRecords} (${DatabaseConstants.colCelestialObjectId})
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_shooting_records_captured_at
      ON ${DatabaseConstants.tableShootingRecords} (${DatabaseConstants.colCapturedAt} DESC)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_celestial_objects_catalog_num
      ON ${DatabaseConstants.tableCelestialObjects}
      (${DatabaseConstants.colCatalog}, ${DatabaseConstants.colNum})
  ''');
}
