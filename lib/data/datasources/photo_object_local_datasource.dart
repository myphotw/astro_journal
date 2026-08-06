import 'package:sqflite/sqflite.dart';

import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';
import '../models/photo_object.dart';

class PhotoObjectLocalDataSource {
  PhotoObjectLocalDataSource({this._database});

  Database? _database;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  Future<List<PhotoObject>> getByPhotoId(String photoId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tablePhotoObjects,
      columns: DatabaseConstants.photoObjectColumns,
      where: '${DatabaseConstants.colPhotoId} = ?',
      whereArgs: [photoId],
      orderBy: '${DatabaseConstants.colAngularDistance} ASC',
    );
    return rows.map(PhotoObject.fromMap).toList();
  }

  /// [photoId]에 대한 기존 검색 결과를 모두 삭제하고 [objects]로 교체한다.
  ///
  /// "Plate Solve 다시 실행" 등으로 검색이 재수행되어도 중복 없이 최신
  /// 결과만 남도록 트랜잭션으로 처리한다.
  Future<void> replaceForPhoto(
    String photoId,
    List<PhotoObject> objects,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        DatabaseConstants.tablePhotoObjects,
        where: '${DatabaseConstants.colPhotoId} = ?',
        whereArgs: [photoId],
      );
      for (final object in objects) {
        await txn.insert(
          DatabaseConstants.tablePhotoObjects,
          object.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteByPhotoId(String photoId) async {
    final db = await _db;
    await db.delete(
      DatabaseConstants.tablePhotoObjects,
      where: '${DatabaseConstants.colPhotoId} = ?',
      whereArgs: [photoId],
    );
  }
}
