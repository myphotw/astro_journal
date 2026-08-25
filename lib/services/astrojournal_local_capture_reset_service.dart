import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/database_constants.dart';
import '../data/database/app_database.dart';
import '../data/datasources/sync_checkpoint_datasource.dart';
import 'app_logger.dart';

abstract interface class AstroJournalLocalCaptureReset {
  Future<void> clearCaptureData({String? resetEventCursor});
}

class AstroJournalLocalCaptureResetService
    implements AstroJournalLocalCaptureReset {
  factory AstroJournalLocalCaptureResetService({
    Database? database,
    Future<Directory> Function()? managedPhotosDirectory,
    Future<void> Function()? onDataChanged,
  }) => AstroJournalLocalCaptureResetService._(
    database,
    managedPhotosDirectory ?? _defaultManagedPhotosDirectory,
    onDataChanged,
  );

  AstroJournalLocalCaptureResetService._(
    this._database,
    this._managedPhotosDirectory,
    this._onDataChanged,
  );

  final Database? _database;
  final Future<Directory> Function() _managedPhotosDirectory;
  final Future<void> Function()? _onDataChanged;

  Future<Database> get _db async => AppDatabase.resolve(_database);

  @override
  Future<void> clearCaptureData({String? resetEventCursor}) async {
    final db = await _db;
    final photosDirectory = await _managedPhotosDirectory();

    await db.transaction((txn) async {
      await txn.delete(DatabaseConstants.tablePhotoObjects);
      await txn.delete(DatabaseConstants.tableShootingRecords);
      await txn.delete(DatabaseConstants.tablePhotos);
      await txn.delete(DatabaseConstants.tableSyncOutbox);
      await txn.delete(DatabaseConstants.tableGalleryCache);
      await txn.update(DatabaseConstants.tableCelestialObjects, {
        DatabaseConstants.colCaptured: 0,
        DatabaseConstants.colCapturedDate: null,
        DatabaseConstants.colPhotoUri: null,
        DatabaseConstants.colExifJson: null,
      });

      final cursor = resetEventCursor?.trim();
      if (cursor != null && cursor.isNotEmpty) {
        await txn.insert(DatabaseConstants.tableGalleryCache, {
          'cache_key':
              'sync:checkpoint:${SyncCheckpointStreams.astroJournalChanges}',
          'payload_json': jsonEncode({'cursor': cursor}),
          'cached_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    });

    await _deleteManagedCopies(photosDirectory);
    try {
      await _onDataChanged?.call();
    } catch (error, stackTrace) {
      AppLogger.error('AstroJournalReset.Refresh', error, stackTrace);
    }
  }

  Future<void> _deleteManagedCopies(Directory directory) async {
    if (!await directory.exists()) return;
    final root = p.normalize(p.absolute(directory.path));
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) continue;
      final candidate = p.normalize(p.absolute(entity.path));
      if (!p.isWithin(root, candidate)) continue;
      try {
        await entity.delete();
      } on FileSystemException catch (error, stackTrace) {
        AppLogger.error('AstroJournalReset.LocalPhoto', error, stackTrace);
      }
    }
  }

  static Future<Directory> _defaultManagedPhotosDirectory() async {
    final appDirectory = await getApplicationDocumentsDirectory();
    return Directory(p.join(appDirectory.path, 'photos'));
  }
}
