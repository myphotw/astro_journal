import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';

abstract class CommonFileLinkDataSource {
  Future<int?> getCommonFileId(String localRecordId);
}

/// Resolves the durable CommonFile identity already stored by upload sync.
class SyncOutboxCommonFileLinkDataSource implements CommonFileLinkDataSource {
  SyncOutboxCommonFileLinkDataSource({this._database});

  Database? _database;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  @override
  Future<int?> getCommonFileId(String localRecordId) async {
    final rows = await (await _db).query(
      DatabaseConstants.tableSyncOutbox,
      columns: const ['payload_json'],
      where: 'local_record_id=?',
      whereArgs: [localRecordId],
      orderBy: 'updated_at DESC',
    );
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row['payload_json'] as String? ?? '{}');
        if (decoded is! Map) continue;
        final value = decoded['common_file_id'];
        if (value is int && value > 0) return value;
        if (value is num && value.toInt() > 0) return value.toInt();
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}
