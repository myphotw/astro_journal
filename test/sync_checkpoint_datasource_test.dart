import 'package:astro_journal/data/datasources/gallery_cache_local_datasource.dart';
import 'package:astro_journal/data/datasources/sync_checkpoint_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      CREATE TABLE gallery_cache (
        cache_key TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        cached_at TEXT NOT NULL
      )
    ''');
  });

  tearDown(() => database.close());

  test('cursor is stored in SQLite and restored by a new instance', () async {
    final first = GalleryCacheSyncCheckpointDataSource(
      GalleryCacheLocalDataSource(database: database),
    );
    await first.writeCursor('common_changes:AstroJournal', 'cursor-42');

    final restored = GalleryCacheSyncCheckpointDataSource(
      GalleryCacheLocalDataSource(database: database),
    );

    expect(
      await restored.readCursor('common_changes:AstroJournal'),
      'cursor-42',
    );
  });
}
