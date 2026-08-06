import 'package:sqflite/sqflite.dart';

import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';
import '../models/photo.dart';

class PhotoLocalDataSource {
  Database? _database;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  Future<List<Photo>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tablePhotos,
      orderBy: '${DatabaseConstants.colCreatedAt} DESC',
    );
    return rows.map(Photo.fromMap).toList();
  }

  Future<void> insert(Photo photo) async {
    final db = await _db;
    await db.insert(
      DatabaseConstants.tablePhotos,
      photo.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete(
      DatabaseConstants.tablePhotos,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
    );
  }
}
