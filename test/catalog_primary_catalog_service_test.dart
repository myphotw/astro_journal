import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_primary_catalog_service.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _insertObject(
  Database db, {
  required String id,
  required String catalog,
  required int num,
  int isFeatured = 0,
  int displayPriority = 9999,
}) async {
  await db.insert(DatabaseConstants.tableCelestialObjects, {
    DatabaseConstants.colId: id,
    DatabaseConstants.colNum: num,
    DatabaseConstants.colCatalog: catalog,
    DatabaseConstants.colName: id,
    DatabaseConstants.colType: '발광성운',
    DatabaseConstants.colConstellation: '백조자리',
    DatabaseConstants.colRa: '20h 45m',
    DatabaseConstants.colDec: '+30° 42\'',
    DatabaseConstants.colMag: '7.0',
    DatabaseConstants.colCaptured: 0,
    DatabaseConstants.colMemo: '',
    DatabaseConstants.colObjectType: '발광성운',
    DatabaseConstants.colSeestarSupported: 0,
    DatabaseConstants.colIsFeatured: isFeatured,
    DatabaseConstants.colDisplayPriority: displayPriority,
    DatabaseConstants.colIsPrimaryCatalog: 1,
    DatabaseConstants.colPrimaryCatalogId: null,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (
      MethodCall methodCall,
    ) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return '.';
      }
      return null;
    });

    await CatalogSearchService.loadGlobalAliases();
  });

  test('marks veil nebula members as secondary except primary', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseConstants.databaseVersion,
        onCreate: (database, version) async {
          await database.execute('''
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
              ${DatabaseConstants.colMemo} TEXT NOT NULL DEFAULT '',
              ${DatabaseConstants.colObjectType} TEXT,
              ${DatabaseConstants.colSeestarSupported} INTEGER NOT NULL DEFAULT 0,
              ${DatabaseConstants.colCommonName} TEXT,
              ${DatabaseConstants.colCrossCatalogRefsJson} TEXT,
              ${DatabaseConstants.colIsFeatured} INTEGER NOT NULL DEFAULT 0,
              ${DatabaseConstants.colDisplayPriority} INTEGER NOT NULL DEFAULT 9999,
              ${DatabaseConstants.colIsPrimaryCatalog} INTEGER NOT NULL DEFAULT 1,
              ${DatabaseConstants.colPrimaryCatalogId} TEXT
            )
          ''');
        },
      ),
    );

    await _insertObject(db, id: 'NGC6960', catalog: 'ngc', num: 6960, isFeatured: 1);
    await _insertObject(db, id: 'NGC6992', catalog: 'ngc', num: 6992);
    await _insertObject(db, id: 'NGC6995', catalog: 'ngc', num: 6995);

    await CatalogPrimaryCatalogService.apply(db);

    final rows = await db.query(DatabaseConstants.tableCelestialObjects);
    final byId = {
      for (final row in rows)
        row[DatabaseConstants.colId] as String: CatalogObject.fromMap(row),
    };

    expect(byId['NGC6960']!.isPrimaryCatalog, isTrue);
    expect(byId['NGC6992']!.isPrimaryCatalog, isFalse);
    expect(byId['NGC6992']!.primaryCatalogId, 'NGC6960');
    expect(byId['NGC6995']!.primaryCatalogId, 'NGC6960');
    expect(
      byId['NGC6960']!.crossCatalogRefs,
      containsAll(['NGC6992', 'NGC6995']),
    );

    await db.close();
  });

  test('hides RCW120 when Sh2-3 is primary via cross refs', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseConstants.databaseVersion,
        onCreate: (database, version) async {
          await database.execute('''
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
              ${DatabaseConstants.colMemo} TEXT NOT NULL DEFAULT '',
              ${DatabaseConstants.colObjectType} TEXT,
              ${DatabaseConstants.colSeestarSupported} INTEGER NOT NULL DEFAULT 0,
              ${DatabaseConstants.colCommonName} TEXT,
              ${DatabaseConstants.colAliasesJson} TEXT,
              ${DatabaseConstants.colCrossCatalogRefsJson} TEXT,
              ${DatabaseConstants.colIsFeatured} INTEGER NOT NULL DEFAULT 0,
              ${DatabaseConstants.colDisplayPriority} INTEGER NOT NULL DEFAULT 9999,
              ${DatabaseConstants.colIsPrimaryCatalog} INTEGER NOT NULL DEFAULT 1,
              ${DatabaseConstants.colPrimaryCatalogId} TEXT
            )
          ''');
        },
      ),
    );

    await db.insert(DatabaseConstants.tableCelestialObjects, {
      DatabaseConstants.colId: 'RCW120',
      DatabaseConstants.colNum: 120,
      DatabaseConstants.colCatalog: 'rcw',
      DatabaseConstants.colName: 'RCW 120',
      DatabaseConstants.colType: '기타',
      DatabaseConstants.colConstellation: '전갈자리',
      DatabaseConstants.colRa: '17h 14m',
      DatabaseConstants.colDec: "-38° 30'",
      DatabaseConstants.colMag: '7.0',
      DatabaseConstants.colCaptured: 0,
      DatabaseConstants.colMemo: '',
      DatabaseConstants.colObjectType: '기타',
      DatabaseConstants.colSeestarSupported: 0,
      DatabaseConstants.colCommonName: 'RCW 120',
      DatabaseConstants.colCrossCatalogRefsJson: '["Sh2-3"]',
      DatabaseConstants.colIsFeatured: 0,
      DatabaseConstants.colDisplayPriority: 9999,
      DatabaseConstants.colIsPrimaryCatalog: 1,
    });
    await db.insert(DatabaseConstants.tableCelestialObjects, {
      DatabaseConstants.colId: 'Sh2-3',
      DatabaseConstants.colNum: 3,
      DatabaseConstants.colCatalog: 'sh2',
      DatabaseConstants.colName: 'Sh2-3',
      DatabaseConstants.colType: '발광성운',
      DatabaseConstants.colConstellation: '전갈자리',
      DatabaseConstants.colRa: '17h 12m',
      DatabaseConstants.colDec: "-38° 28'",
      DatabaseConstants.colMag: '7.0',
      DatabaseConstants.colCaptured: 0,
      DatabaseConstants.colMemo: '',
      DatabaseConstants.colObjectType: '발광성운',
      DatabaseConstants.colSeestarSupported: 1,
      DatabaseConstants.colCommonName: 'Green Ring 성운',
      DatabaseConstants.colCrossCatalogRefsJson: '["RCW120"]',
      DatabaseConstants.colIsFeatured: 1,
      DatabaseConstants.colDisplayPriority: 100,
      DatabaseConstants.colIsPrimaryCatalog: 1,
    });

    await CatalogPrimaryCatalogService.apply(db);

    final rcw = CatalogObject.fromMap(
      (await db.query(
        DatabaseConstants.tableCelestialObjects,
        where: '${DatabaseConstants.colId} = ?',
        whereArgs: ['RCW120'],
      ))
          .single,
    );
    final sh2 = CatalogObject.fromMap(
      (await db.query(
        DatabaseConstants.tableCelestialObjects,
        where: '${DatabaseConstants.colId} = ?',
        whereArgs: ['Sh2-3'],
      ))
          .single,
    );

    expect(sh2.isPrimaryCatalog, isTrue);
    expect(rcw.isPrimaryCatalog, isFalse);
    expect(rcw.primaryCatalogId, 'Sh2-3');

    await db.close();
  });

  test('replaces catalog-id common name with secondary Korean name', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseConstants.databaseVersion,
        onCreate: (database, version) async {
          await database.execute('''
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
              ${DatabaseConstants.colMemo} TEXT NOT NULL DEFAULT '',
              ${DatabaseConstants.colObjectType} TEXT,
              ${DatabaseConstants.colSeestarSupported} INTEGER NOT NULL DEFAULT 0,
              ${DatabaseConstants.colCommonName} TEXT,
              ${DatabaseConstants.colAliasesJson} TEXT,
              ${DatabaseConstants.colCrossCatalogRefsJson} TEXT,
              ${DatabaseConstants.colIsFeatured} INTEGER NOT NULL DEFAULT 0,
              ${DatabaseConstants.colDisplayPriority} INTEGER NOT NULL DEFAULT 9999,
              ${DatabaseConstants.colIsPrimaryCatalog} INTEGER NOT NULL DEFAULT 1,
              ${DatabaseConstants.colPrimaryCatalogId} TEXT
            )
          ''');
        },
      ),
    );

    await db.insert(DatabaseConstants.tableCelestialObjects, {
      DatabaseConstants.colId: 'NGC2264',
      DatabaseConstants.colNum: 2264,
      DatabaseConstants.colCatalog: 'ngc',
      DatabaseConstants.colName: 'NGC 2264',
      DatabaseConstants.colType: '기타',
      DatabaseConstants.colConstellation: '외뿔소자리',
      DatabaseConstants.colRa: '06h 41m',
      DatabaseConstants.colDec: "+09° 53'",
      DatabaseConstants.colMag: '3.9',
      DatabaseConstants.colCaptured: 0,
      DatabaseConstants.colMemo: '',
      DatabaseConstants.colObjectType: '기타',
      DatabaseConstants.colSeestarSupported: 0,
      DatabaseConstants.colCommonName: 'NGC 2264',
      DatabaseConstants.colCrossCatalogRefsJson: '["Sh2-273"]',
      DatabaseConstants.colIsFeatured: 1,
      DatabaseConstants.colDisplayPriority: 100,
      DatabaseConstants.colIsPrimaryCatalog: 1,
    });
    await db.insert(DatabaseConstants.tableCelestialObjects, {
      DatabaseConstants.colId: 'Sh2-273',
      DatabaseConstants.colNum: 273,
      DatabaseConstants.colCatalog: 'sh2',
      DatabaseConstants.colName: '크리스마스 트리 성운',
      DatabaseConstants.colType: '발광성운',
      DatabaseConstants.colConstellation: '외뿔소자리',
      DatabaseConstants.colRa: '06h 41m',
      DatabaseConstants.colDec: "+09° 53'",
      DatabaseConstants.colMag: '-',
      DatabaseConstants.colCaptured: 0,
      DatabaseConstants.colMemo: '',
      DatabaseConstants.colObjectType: '발광성운',
      DatabaseConstants.colSeestarSupported: 1,
      DatabaseConstants.colCommonName: '크리스마스 트리 성운',
      DatabaseConstants.colCrossCatalogRefsJson: '["NGC2264"]',
      DatabaseConstants.colIsFeatured: 0,
      DatabaseConstants.colDisplayPriority: 9999,
      DatabaseConstants.colIsPrimaryCatalog: 1,
    });

    await CatalogPrimaryCatalogService.apply(db);

    final ngc = CatalogObject.fromMap(
      (await db.query(
        DatabaseConstants.tableCelestialObjects,
        where: '${DatabaseConstants.colId} = ?',
        whereArgs: ['NGC2264'],
      ))
          .single,
    );
    final sh2 = CatalogObject.fromMap(
      (await db.query(
        DatabaseConstants.tableCelestialObjects,
        where: '${DatabaseConstants.colId} = ?',
        whereArgs: ['Sh2-273'],
      ))
          .single,
    );

    expect(ngc.isPrimaryCatalog, isTrue);
    expect(sh2.isPrimaryCatalog, isFalse);
    expect(ngc.commonName, '크리스마스 트리 성운');

    await db.close();
  });

  test('one-way cross refs do not crash discovery', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseConstants.databaseVersion,
        onCreate: (database, version) async {
          await database.execute('''
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
              ${DatabaseConstants.colMemo} TEXT NOT NULL DEFAULT '',
              ${DatabaseConstants.colObjectType} TEXT,
              ${DatabaseConstants.colSeestarSupported} INTEGER NOT NULL DEFAULT 0,
              ${DatabaseConstants.colCommonName} TEXT,
              ${DatabaseConstants.colAliasesJson} TEXT,
              ${DatabaseConstants.colCrossCatalogRefsJson} TEXT,
              ${DatabaseConstants.colIsFeatured} INTEGER NOT NULL DEFAULT 0,
              ${DatabaseConstants.colDisplayPriority} INTEGER NOT NULL DEFAULT 9999,
              ${DatabaseConstants.colIsPrimaryCatalog} INTEGER NOT NULL DEFAULT 1,
              ${DatabaseConstants.colPrimaryCatalogId} TEXT
            )
          ''');
        },
      ),
    );

    // A -> B 단방향 참조: B는 edges에 키가 없어 기존에 ! crash가 발생했다.
    await db.insert(DatabaseConstants.tableCelestialObjects, {
      DatabaseConstants.colId: 'LBN833',
      DatabaseConstants.colNum: 833,
      DatabaseConstants.colCatalog: 'lbn',
      DatabaseConstants.colName: 'LBN 833',
      DatabaseConstants.colType: '발광성운',
      DatabaseConstants.colConstellation: '황소자리',
      DatabaseConstants.colRa: '05h 34m',
      DatabaseConstants.colDec: "+22° 01'",
      DatabaseConstants.colMag: '8.4',
      DatabaseConstants.colCaptured: 0,
      DatabaseConstants.colMemo: '',
      DatabaseConstants.colObjectType: '발광성운',
      DatabaseConstants.colSeestarSupported: 0,
      DatabaseConstants.colCrossCatalogRefsJson: '["M1"]',
      DatabaseConstants.colIsFeatured: 0,
      DatabaseConstants.colDisplayPriority: 9999,
      DatabaseConstants.colIsPrimaryCatalog: 1,
    });
    await db.insert(DatabaseConstants.tableCelestialObjects, {
      DatabaseConstants.colId: 'M1',
      DatabaseConstants.colNum: 1,
      DatabaseConstants.colCatalog: 'messier',
      DatabaseConstants.colName: '게 성운',
      DatabaseConstants.colType: '초신성잔해',
      DatabaseConstants.colConstellation: '황소자리',
      DatabaseConstants.colRa: '05h 34m',
      DatabaseConstants.colDec: "+22° 01'",
      DatabaseConstants.colMag: '8.4',
      DatabaseConstants.colCaptured: 0,
      DatabaseConstants.colMemo: '',
      DatabaseConstants.colObjectType: '초신성잔해',
      DatabaseConstants.colSeestarSupported: 1,
      DatabaseConstants.colCrossCatalogRefsJson: null,
      DatabaseConstants.colIsFeatured: 1,
      DatabaseConstants.colDisplayPriority: 1,
      DatabaseConstants.colIsPrimaryCatalog: 1,
    });

    await CatalogPrimaryCatalogService.apply(db);

    final rows = await db.query(DatabaseConstants.tableCelestialObjects);
    expect(rows, hasLength(2));

    await db.close();
  });
}
