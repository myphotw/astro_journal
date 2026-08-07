import 'package:sqflite/sqflite.dart';

import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';

class GalleryCacheEntry {
  const GalleryCacheEntry({
    required this.key,
    required this.payloadJson,
    required this.cachedAt,
  });

  final String key;
  final String payloadJson;
  final DateTime cachedAt;
}

abstract class GalleryCacheDataSource {
  Future<GalleryCacheEntry?> read(String key);
  Future<void> write(GalleryCacheEntry entry);
}

class GalleryCacheLocalDataSource implements GalleryCacheDataSource {
  factory GalleryCacheLocalDataSource({Database? database}) =>
      GalleryCacheLocalDataSource._(database);

  GalleryCacheLocalDataSource._(this._database);

  Database? _database;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  @override
  Future<GalleryCacheEntry?> read(String key) async {
    final rows = await (await _db).query(
      DatabaseConstants.tableGalleryCache,
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return GalleryCacheEntry(
      key: row['cache_key'] as String,
      payloadJson: row['payload_json'] as String,
      cachedAt: DateTime.parse(row['cached_at'] as String),
    );
  }

  @override
  Future<void> write(GalleryCacheEntry entry) async {
    await (await _db).insert(
      DatabaseConstants.tableGalleryCache,
      {
        'cache_key': entry.key,
        'payload_json': entry.payloadJson,
        'cached_at': entry.cachedAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
