import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/database_constants.dart';
import '../../core/database/sqflite_bootstrap.dart';
import '../../services/catalog_featured_ranking_service.dart';
import '../../services/catalog_fts_service.dart';
import '../../services/catalog_hanzi_cleanup_migration.dart';
import '../../services/catalog_metadata_migration.dart';
import '../../services/catalog_object_type_migration.dart';
import '../../services/catalog_primary_catalog_service.dart';
import '../../services/catalog_search_service.dart';

class AppDatabase {
  AppDatabase._();

  static Database? _database;

  static Future<Database> get instance async {
    final existing = _database;
    // backup 등으로 close된 뒤에도 stale 핸들을 반환하지 않는다.
    if (existing != null && !existing.isOpen) {
      _database = null;
    }
    _database ??= await _open();
    return _database!;
  }

  /// DataSource 캐시가 닫혀 있으면 [instance]로 다시 연다.
  static Future<Database> resolve(Database? cached) async {
    if (cached != null && cached.isOpen) return cached;
    return instance;
  }

  static Future<Database> _open() async {
    final dbPath = await getAppDatabasesPath();
    final path = join(dbPath, DatabaseConstants.databaseName);

    return openDatabase(
      path,
      version: DatabaseConstants.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
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
        ${DatabaseConstants.colAnalysisStatus} TEXT NOT NULL DEFAULT 'COMPLETED',
        FOREIGN KEY (${DatabaseConstants.colCelestialObjectId})
          REFERENCES ${DatabaseConstants.tableCelestialObjects} (${DatabaseConstants.colId})
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DatabaseConstants.tablePhotos} (
        ${DatabaseConstants.colId} TEXT PRIMARY KEY,
        ${DatabaseConstants.colLocalPath} TEXT NOT NULL,
        ${DatabaseConstants.colOriginalFilename} TEXT,
        ${DatabaseConstants.colCreatedAt} TEXT NOT NULL,
        ${DatabaseConstants.colExifJson} TEXT
      )
    ''');

    await _createPhotoObjectsTable(db);
    await _createEquipmentTables(db);
    await _createObservationSiteFavoritesTable(db);
    await _createSyncOutboxTable(db);
    await _createGalleryCacheTable(db);
    await _createIndexes(db);
    await CatalogFtsService.ensureSchema(db);
  }

  /// Plate Solve WCS 기반으로 검색된, 사진 안에 포함되는 천체 목록.
  ///
  /// [DatabaseConstants.colPhotoId]는 `shooting_records.id`를,
  /// [DatabaseConstants.colCatalogId]는 `celestial_objects.id`를 참조한다.
  /// 천체 상세정보는 저장하지 않고 Catalog를 참조한다.
  static Future<void> _createPhotoObjectsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseConstants.tablePhotoObjects} (
        ${DatabaseConstants.colId} TEXT PRIMARY KEY,
        ${DatabaseConstants.colPhotoId} TEXT NOT NULL,
        ${DatabaseConstants.colCatalogId} TEXT NOT NULL,
        ${DatabaseConstants.colCatalogType} TEXT NOT NULL,
        ${DatabaseConstants.colDisplayName} TEXT NOT NULL,
        ${DatabaseConstants.colRa} REAL NOT NULL,
        ${DatabaseConstants.colDec} REAL NOT NULL,
        ${DatabaseConstants.colAngularDistance} REAL NOT NULL,
        ${DatabaseConstants.colConfidence} REAL NOT NULL,
        ${DatabaseConstants.colIsPrimaryTarget} INTEGER NOT NULL DEFAULT 0,
        ${DatabaseConstants.colIsVisible} INTEGER NOT NULL DEFAULT 1,
        ${DatabaseConstants.colPixelX} REAL,
        ${DatabaseConstants.colPixelY} REAL,
        ${DatabaseConstants.colCreatedAt} TEXT NOT NULL,
        FOREIGN KEY (${DatabaseConstants.colPhotoId})
          REFERENCES ${DatabaseConstants.tableShootingRecords} (${DatabaseConstants.colId}),
        FOREIGN KEY (${DatabaseConstants.colCatalogId})
          REFERENCES ${DatabaseConstants.tableCelestialObjects} (${DatabaseConstants.colId})
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_photo_objects_photo_id
        ON ${DatabaseConstants.tablePhotoObjects} (${DatabaseConstants.colPhotoId})
    ''');
  }

  static Future<void> _createObservationSiteFavoritesTable(Database db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseConstants.tableObservationSiteFavorites} (
        ${DatabaseConstants.colId} TEXT PRIMARY KEY,
        ${DatabaseConstants.colName} TEXT NOT NULL,
        ${DatabaseConstants.colLatitude} REAL NOT NULL,
        ${DatabaseConstants.colLongitude} REAL NOT NULL,
        ${DatabaseConstants.colBortle} INTEGER,
        ${DatabaseConstants.colSqm} REAL,
        ${DatabaseConstants.colBrightnessGrade} TEXT,
        ${DatabaseConstants.colCreatedAt} TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createEquipmentTables(Database db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseConstants.tableEquipment} (
        ${DatabaseConstants.colId} TEXT PRIMARY KEY,
        ${DatabaseConstants.colName} TEXT NOT NULL,
        ${DatabaseConstants.colEquipmentKind} TEXT NOT NULL,
        ${DatabaseConstants.colEquipmentPurpose} TEXT NOT NULL,
        ${DatabaseConstants.colIsActive} INTEGER NOT NULL DEFAULT 1,
        ${DatabaseConstants.colFocalLengthMm} REAL,
        ${DatabaseConstants.colFovDegrees} REAL,
        ${DatabaseConstants.colFovWidthDegrees} REAL,
        ${DatabaseConstants.colFovHeightDegrees} REAL,
        ${DatabaseConstants.colApertureMm} REAL,
        ${DatabaseConstants.colSortOrder} INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DatabaseConstants.tableEyepieces} (
        ${DatabaseConstants.colId} TEXT PRIMARY KEY,
        ${DatabaseConstants.colEquipmentId} TEXT NOT NULL,
        ${DatabaseConstants.colName} TEXT NOT NULL,
        ${DatabaseConstants.colFocalLengthMm} REAL NOT NULL,
        ${DatabaseConstants.colAfovDegrees} REAL NOT NULL,
        ${DatabaseConstants.colSortOrder} INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (${DatabaseConstants.colEquipmentId})
          REFERENCES ${DatabaseConstants.tableEquipment} (${DatabaseConstants.colId})
          ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DatabaseConstants.tablePhotos} (
          ${DatabaseConstants.colId} TEXT PRIMARY KEY,
          ${DatabaseConstants.colLocalPath} TEXT NOT NULL,
          ${DatabaseConstants.colCreatedAt} TEXT NOT NULL,
          ${DatabaseConstants.colExifJson} TEXT
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tablePhotos}
        ADD COLUMN ${DatabaseConstants.colExifJson} TEXT
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableShootingRecords}
        ADD COLUMN ${DatabaseConstants.colLocation} TEXT
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableShootingRecords}
        ADD COLUMN ${DatabaseConstants.colMetadataJson} TEXT
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableShootingRecords}
        ADD COLUMN ${DatabaseConstants.colOriginalFilename} TEXT
      ''');
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tablePhotos}
        ADD COLUMN ${DatabaseConstants.colOriginalFilename} TEXT
      ''');
    }
    if (oldVersion < 7) {
      await _migrateToV7(db);
    }
    if (oldVersion < 8) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colAliasesJson} TEXT
      ''');
    }
    if (oldVersion < 9) {
      await _removeBarnardAndLdnCatalog(db);
    }
    if (oldVersion < 10) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableShootingRecords}
        ADD COLUMN ${DatabaseConstants.colIsFavorite} INTEGER NOT NULL DEFAULT 0
      ''');
    }
    if (oldVersion < 11) {
      await _migrateToV11(db);
    }
    if (oldVersion < 12) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colTagsJson} TEXT
      ''');
    }
    if (oldVersion < 13) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colPeakMonth} INTEGER
      ''');
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colBestSeason} TEXT
      ''');
      await CatalogMetadataMigration.backfillSeason(db);
    }
    if (oldVersion < 14) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colAngularSize} TEXT
      ''');
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colDescription} TEXT
      ''');
      await CatalogMetadataMigration.backfillAll(db);
    }
    if (oldVersion < 15) {
      await _createEquipmentTables(db);
    }
    if (oldVersion < 16) {
      await _migrateToV16EquipmentFov(db);
    }
    if (oldVersion < 17) {
      await _createObservationSiteFavoritesTable(db);
    }
    if (oldVersion < 18) {
      await _createIndexes(db);
    }
    if (oldVersion < 19) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colCrossCatalogRefsJson} TEXT
      ''');
    }
    if (oldVersion < 20) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colSearchKeywords} TEXT
      ''');
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colMajorAxis} REAL
      ''');
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colMinorAxis} REAL
      ''');
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colPositionAngle} REAL
      ''');
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colDataSource} TEXT
      ''');
    }
    if (oldVersion < 21) {
      await CatalogFtsService.ensureSchema(db);
      await CatalogFtsService.rebuild(db);
    }
    if (oldVersion < 22) {
      await CatalogHanziCleanupMigration.cleanup(db);
    }
    if (oldVersion < 23) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colIsFeatured} INTEGER NOT NULL DEFAULT 0
      ''');
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colDisplayPriority} INTEGER NOT NULL
        DEFAULT ${DatabaseConstants.defaultDisplayPriority}
      ''');
      await CatalogFeaturedRankingService.apply(db);
    }
    if (oldVersion < 24) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colIsPrimaryCatalog} INTEGER NOT NULL DEFAULT 1
      ''');
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colPrimaryCatalogId} TEXT
      ''');
      await CatalogPrimaryCatalogService.apply(db);
    }
    if (oldVersion < 25) {
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_celestial_objects_object_type
          ON ${DatabaseConstants.tableCelestialObjects}
          (${DatabaseConstants.colObjectType})
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_celestial_objects_featured
          ON ${DatabaseConstants.tableCelestialObjects}
          (${DatabaseConstants.colIsFeatured}, ${DatabaseConstants.colDisplayPriority})
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_celestial_objects_primary
          ON ${DatabaseConstants.tableCelestialObjects}
          (${DatabaseConstants.colIsPrimaryCatalog})
      ''');
      await CatalogObjectTypeMigration.apply(
        db,
        globalAliases: CatalogSearchService.globalAliases,
        globalCrossCatalog: CatalogSearchService.globalCrossCatalog,
      );
    }
    if (oldVersion < 26) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
        ADD COLUMN ${DatabaseConstants.colDistanceLy} REAL
      ''');
    }
    if (oldVersion < 27) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableShootingRecords}
        ADD COLUMN ${DatabaseConstants.colPlateSolveJson} TEXT
      ''');
    }
    if (oldVersion < 28) {
      await _createPhotoObjectsTable(db);
    }
    if (oldVersion < 29) {
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableShootingRecords}
        ADD COLUMN ${DatabaseConstants.colDetectMethod} TEXT
      ''');
      await db.execute('''
        ALTER TABLE ${DatabaseConstants.tableShootingRecords}
        ADD COLUMN ${DatabaseConstants.colAnalysisStatus} TEXT NOT NULL DEFAULT 'COMPLETED'
      ''');
    }
    if (oldVersion < 30) {
      await _createSyncOutboxTable(db);
    }
    if (oldVersion < 31) {
      await _createGalleryCacheTable(db);
    }
  }

  static Future<void> _createGalleryCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseConstants.tableGalleryCache} (
        cache_key TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        cached_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createSyncOutboxTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseConstants.tableSyncOutbox} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id TEXT NOT NULL UNIQUE,
        operation_type TEXT NOT NULL,
        local_record_id TEXT,
        local_photo_id TEXT,
        client_file_id TEXT,
        client_record_id TEXT,
        backend_file_id TEXT,
        backend_record_id TEXT,
        upload_job_id TEXT,
        state TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT,
        payload_json TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending
      ON ${DatabaseConstants.tableSyncOutbox} (state, next_retry_at, created_at)
    ''');
  }

  static Future<void> _createIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_shooting_records_object_id
        ON ${DatabaseConstants.tableShootingRecords} (${DatabaseConstants.colCelestialObjectId})
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_shooting_records_captured_at
        ON ${DatabaseConstants.tableShootingRecords} (${DatabaseConstants.colCapturedAt} DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_shooting_records_filename
        ON ${DatabaseConstants.tableShootingRecords} (${DatabaseConstants.colOriginalFilename})
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_shooting_records_favorite
        ON ${DatabaseConstants.tableShootingRecords} (${DatabaseConstants.colIsFavorite})
        WHERE ${DatabaseConstants.colIsFavorite} = 1
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_celestial_objects_catalog_num
        ON ${DatabaseConstants.tableCelestialObjects}
        (${DatabaseConstants.colCatalog}, ${DatabaseConstants.colNum})
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_celestial_objects_captured
        ON ${DatabaseConstants.tableCelestialObjects} (${DatabaseConstants.colCaptured})
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_celestial_objects_object_type
        ON ${DatabaseConstants.tableCelestialObjects}
        (${DatabaseConstants.colObjectType})
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_celestial_objects_featured
        ON ${DatabaseConstants.tableCelestialObjects}
        (${DatabaseConstants.colIsFeatured}, ${DatabaseConstants.colDisplayPriority})
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_celestial_objects_primary
        ON ${DatabaseConstants.tableCelestialObjects}
        (${DatabaseConstants.colIsPrimaryCatalog})
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_eyepieces_equipment_id
        ON ${DatabaseConstants.tableEyepieces} (${DatabaseConstants.colEquipmentId})
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_photos_created_at
        ON ${DatabaseConstants.tablePhotos} (${DatabaseConstants.colCreatedAt} DESC)
    ''');
  }

  static Future<void> _migrateToV16EquipmentFov(Database db) async {
    await db.execute('''
      ALTER TABLE ${DatabaseConstants.tableEquipment}
      ADD COLUMN ${DatabaseConstants.colFovWidthDegrees} REAL
    ''');
    await db.execute('''
      ALTER TABLE ${DatabaseConstants.tableEquipment}
      ADD COLUMN ${DatabaseConstants.colFovHeightDegrees} REAL
    ''');
    await db.execute('''
      UPDATE ${DatabaseConstants.tableEquipment}
      SET ${DatabaseConstants.colFovWidthDegrees} = ${DatabaseConstants.colFovDegrees},
          ${DatabaseConstants.colFovHeightDegrees} = ${DatabaseConstants.colFovDegrees}
      WHERE ${DatabaseConstants.colFovDegrees} IS NOT NULL
    ''');
  }

  static Future<void> _migrateToV11(Database db) async {
    await db.execute('''
      ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
      ADD COLUMN ${DatabaseConstants.colCommonName} TEXT
    ''');
    await db.execute('''
      ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
      ADD COLUMN ${DatabaseConstants.colObjectType} TEXT
    ''');
    await db.execute('''
      ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
      ADD COLUMN ${DatabaseConstants.colSeestarSupported} INTEGER NOT NULL DEFAULT 0
    ''');
    await db.execute('''
      ALTER TABLE ${DatabaseConstants.tableCelestialObjects}
      ADD COLUMN ${DatabaseConstants.colSuffix} TEXT
    ''');
    await db.execute('''
      UPDATE ${DatabaseConstants.tableCelestialObjects}
      SET ${DatabaseConstants.colCommonName} = ${DatabaseConstants.colName},
          ${DatabaseConstants.colObjectType} = ${DatabaseConstants.colType}
    ''');
  }

  static Future<void> _removeBarnardAndLdnCatalog(Database db) async {
    final rows = await db.query(
      DatabaseConstants.tableCelestialObjects,
      columns: [DatabaseConstants.colId],
      where: '${DatabaseConstants.colCatalog} IN (?, ?)',
      whereArgs: ['barnard', 'ldn'],
    );
    if (rows.isEmpty) return;

    final ids = rows.map((r) => r[DatabaseConstants.colId] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(', ');

    await db.delete(
      DatabaseConstants.tableShootingRecords,
      where: '${DatabaseConstants.colCelestialObjectId} IN ($placeholders)',
      whereArgs: ids,
    );
    await db.delete(
      DatabaseConstants.tableCelestialObjects,
      where: '${DatabaseConstants.colCatalog} IN (?, ?)',
      whereArgs: ['barnard', 'ldn'],
    );
  }

  static Future<void> _migrateToV7(Database db) async {
    await db.execute('''
      ALTER TABLE ${DatabaseConstants.tableShootingRecords}
      ADD COLUMN ${DatabaseConstants.colIsRepresentative} INTEGER NOT NULL DEFAULT 0
    ''');

    await _mergeMilkyWayCatalog(db);
    await _initializeRepresentativePhotos(db);
  }

  static Future<void> _mergeMilkyWayCatalog(Database db) async {
    const oldMilkyIds = ['mw_1', 'mw_2', 'mw_3', 'mw_4', 'mw_5'];
    const newMilkyId = 'mw';

    await db.update(
      DatabaseConstants.tableShootingRecords,
      {DatabaseConstants.colCelestialObjectId: newMilkyId},
      where: '${DatabaseConstants.colCelestialObjectId} IN (?, ?, ?, ?, ?)',
      whereArgs: oldMilkyIds,
    );

    final oldRows = await db.query(
      DatabaseConstants.tableCelestialObjects,
      where: '${DatabaseConstants.colCatalog} = ?',
      whereArgs: ['milky'],
    );

    var captured = false;
    String? capturedDate;
    for (final row in oldRows) {
      if ((row[DatabaseConstants.colCaptured] as int? ?? 0) == 1) {
        captured = true;
        final date = row[DatabaseConstants.colCapturedDate] as String?;
        if (date != null &&
            (capturedDate == null || date.compareTo(capturedDate) > 0)) {
          capturedDate = date;
        }
      }
    }

    await db.delete(
      DatabaseConstants.tableCelestialObjects,
      where: '${DatabaseConstants.colCatalog} = ?',
      whereArgs: ['milky'],
    );

    await db.insert(
      DatabaseConstants.tableCelestialObjects,
      {
        DatabaseConstants.colId: newMilkyId,
        DatabaseConstants.colNum: 1,
        DatabaseConstants.colCatalog: 'milky',
        DatabaseConstants.colName: '은하수',
        DatabaseConstants.colType: '은하',
        DatabaseConstants.colConstellation: '-',
        DatabaseConstants.colRa: '-',
        DatabaseConstants.colDec: '-',
        DatabaseConstants.colMag: '-',
        DatabaseConstants.colCaptured: captured ? 1 : 0,
        DatabaseConstants.colCapturedDate: capturedDate,
        DatabaseConstants.colMemo: '',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _initializeRepresentativePhotos(Database db) async {
    final rows = await db.query(
      DatabaseConstants.tableShootingRecords,
      orderBy: '${DatabaseConstants.colCapturedAt} DESC',
    );

    final assigned = <String>{};
    for (final row in rows) {
      final objectId = row[DatabaseConstants.colCelestialObjectId] as String;
      final photoUri = row[DatabaseConstants.colPhotoUri] as String?;
      if (assigned.contains(objectId)) continue;
      if (photoUri == null || photoUri.isEmpty) continue;

      await db.update(
        DatabaseConstants.tableShootingRecords,
        {DatabaseConstants.colIsRepresentative: 1},
        where: '${DatabaseConstants.colId} = ?',
        whereArgs: [row[DatabaseConstants.colId]],
      );
      assigned.add(objectId);
    }
  }

  static Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
