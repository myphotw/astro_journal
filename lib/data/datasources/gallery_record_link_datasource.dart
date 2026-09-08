import 'package:sqflite/sqflite.dart';

import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';

abstract class GalleryRecordLinkDataSource {
  Future<Map<String, String>> localIdsByBackendRecordId();
}

class SyncOutboxGalleryRecordLinkDataSource
    implements GalleryRecordLinkDataSource {
  factory SyncOutboxGalleryRecordLinkDataSource({Database? database}) =>
      SyncOutboxGalleryRecordLinkDataSource._(database);

  SyncOutboxGalleryRecordLinkDataSource._(this._database);

  Database? _database;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  @override
  Future<Map<String, String>> localIdsByBackendRecordId() async {
    final rows = await (await _db).query(
      DatabaseConstants.tableSyncOutbox,
      columns: const ['backend_record_id', 'local_record_id'],
      where:
          "operation_type='PHOTO_UPLOAD_AND_RECORD' "
          'AND backend_record_id IS NOT NULL '
          'AND local_record_id IS NOT NULL '
          "AND state!='CANCELLED'",
      orderBy:
          "CASE WHEN state='SYNCED' THEN 0 ELSE 1 END, "
          'updated_at DESC, id DESC',
    );
    final links = <String, String>{};
    for (final row in rows) {
      links.putIfAbsent(
        row['backend_record_id'] as String,
        () => row['local_record_id'] as String,
      );
    }
    return links;
  }
}

class EmptyGalleryRecordLinkDataSource implements GalleryRecordLinkDataSource {
  const EmptyGalleryRecordLinkDataSource();

  @override
  Future<Map<String, String>> localIdsByBackendRecordId() async => const {};
}
