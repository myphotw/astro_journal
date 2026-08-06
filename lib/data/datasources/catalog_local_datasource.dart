import 'package:sqflite/sqflite.dart' show Database, ConflictAlgorithm;

import '../../services/catalog_fts_service.dart';
import '../../core/constants/catalog_type.dart';
import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';
import '../models/catalog_object.dart';

class CatalogLocalDataSource {
  CatalogLocalDataSource({this._database});

  Database? _database;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  Future<List<CatalogObject>> getAll({bool listOnly = true}) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableCelestialObjects,
      columns: listOnly
          ? DatabaseConstants.celestialObjectListColumns
          : DatabaseConstants.celestialObjectColumns,
      orderBy: 'CASE ${DatabaseConstants.colCatalog} '
              "WHEN 'messier' THEN 1 "
              "WHEN 'ngc' THEN 2 "
              "WHEN 'ic' THEN 3 "
              "WHEN 'caldwell' THEN 4 "
              "WHEN 'sh2' THEN 5 "
              "WHEN 'rcw' THEN 6 "
              "WHEN 'vdb' THEN 7 "
              "WHEN 'star' THEN 8 "
              "WHEN 'solar' THEN 9 "
              "WHEN 'milky' THEN 10 "
              'ELSE 11 END, '
          '${_catalogInternalOrderBy()}',
    );
    return rows.map(CatalogObject.fromMap).toList();
  }

  Future<CatalogObject?> getById(String id) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableCelestialObjects,
      columns: DatabaseConstants.celestialObjectColumns,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CatalogObject.fromMap(rows.first);
  }

  Future<List<CatalogObject>> getByCatalog(CatalogType type) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableCelestialObjects,
      columns: DatabaseConstants.celestialObjectColumns,
      where: '${DatabaseConstants.colCatalog} = ?',
      whereArgs: [type.value],
      orderBy: _catalogInternalOrderBy(),
    );
    return rows.map(CatalogObject.fromMap).toList();
  }

  /// 카탈로그 내부 정렬:
  /// Messier는 번호순을 유지하고, 그 외 카탈로그는
  /// 대표 천체(is_featured) → 표시 우선순위(display_priority) → 이름순으로 정렬한다.
  static String _catalogInternalOrderBy() {
    final messierNum = "CASE WHEN ${DatabaseConstants.colCatalog} = 'messier' "
        'THEN ${DatabaseConstants.colNum} ELSE 0 END';
    return '$messierNum, '
        '${DatabaseConstants.colIsFeatured} DESC, '
        '${DatabaseConstants.colDisplayPriority} ASC, '
        '${DatabaseConstants.colName} ASC';
  }

  Future<List<CatalogObject>> search(String query, {int limit = 50}) async {
    final db = await _db;
    final ids = await CatalogFtsService.searchObjectIds(
      db,
      query,
      limit: limit,
    );
    if (ids.isEmpty) {
      return const [];
    }

    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await db.query(
      DatabaseConstants.tableCelestialObjects,
      columns: DatabaseConstants.celestialObjectColumns,
      where: '${DatabaseConstants.colId} IN ($placeholders)',
      whereArgs: ids,
    );

    final byId = {
      for (final row in rows) row[DatabaseConstants.colId] as String: row,
    };
    return ids
        .where(byId.containsKey)
        .map((id) => CatalogObject.fromMap(byId[id]!))
        .toList(growable: false);
  }

  Future<void> rebuildSearchIndex({
    Map<String, List<String>> globalAliases = const {},
    Map<String, List<String>> globalCrossCatalog = const {},
  }) async {
    final db = await _db;
    await CatalogFtsService.rebuild(
      db,
      globalAliases: globalAliases,
      globalCrossCatalog: globalCrossCatalog,
    );
  }

  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {
    final db = await _db;
    final values = <String, dynamic>{
      DatabaseConstants.colCaptured: captured ? 1 : 0,
    };
    if (capturedDate != null) {
      values[DatabaseConstants.colCapturedDate] = capturedDate;
    }
    await db.update(
      DatabaseConstants.tableCelestialObjects,
      values,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
    );
  }

  Future<void> insert(CatalogObject object) async {
    final db = await _db;
    await db.insert(
      DatabaseConstants.tableCelestialObjects,
      object.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete(
      DatabaseConstants.tableCelestialObjects,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
    );
  }
}
