import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Database;

import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';
import '../models/observation_site_favorite.dart';

class ObservationSiteFavoriteLocalDataSource {
  ObservationSiteFavoriteLocalDataSource({this._database});

  Database? _database;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  Future<List<ObservationSiteFavorite>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableObservationSiteFavorites,
      orderBy: '${DatabaseConstants.colCreatedAt} DESC',
    );
    return rows.map(ObservationSiteFavorite.fromMap).toList();
  }

  Future<ObservationSiteFavorite?> getById(String id) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableObservationSiteFavorites,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ObservationSiteFavorite.fromMap(rows.first);
  }

  Future<void> insert(ObservationSiteFavorite favorite) async {
    final db = await _db;
    await db.insert(
      DatabaseConstants.tableObservationSiteFavorites,
      favorite.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete(
      DatabaseConstants.tableObservationSiteFavorites,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
    );
  }
}
