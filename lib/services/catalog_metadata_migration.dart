import 'package:sqflite/sqflite.dart';

import '../core/constants/database_constants.dart';
import '../data/models/catalog_object.dart';
import 'catalog_metadata_enricher.dart';

/// celestial_objects 테이블의 계절·크기·설명 컬럼을 채운다.
class CatalogMetadataMigration {
  CatalogMetadataMigration._();

  static const _enricher = CatalogMetadataEnricher();

  /// v13: peak_month, best_season만 채운다.
  static Future<void> backfillSeason(Database db) async {
    await _backfill(
      db,
      includeSeason: true,
      includeSizeAndDescription: false,
    );
  }

  /// v14+: 계절·크기·설명을 모두 채운다.
  static Future<void> backfillAll(Database db) async {
    await _backfill(
      db,
      includeSeason: true,
      includeSizeAndDescription: true,
    );
  }

  static Future<void> _backfill(
    Database db, {
    required bool includeSeason,
    required bool includeSizeAndDescription,
  }) async {
    final rows = await db.query(DatabaseConstants.tableCelestialObjects);
    if (rows.isEmpty) return;

    await db.transaction((txn) async {
      for (final row in rows) {
        final object = CatalogObject.fromMap(row);
        final enriched = _enricher.enrich(object);
        final values = <String, dynamic>{};

        if (includeSeason) {
          values[DatabaseConstants.colPeakMonth] = enriched.peakMonth;
          values[DatabaseConstants.colBestSeason] = enriched.bestSeason;
        }
        if (includeSizeAndDescription) {
          values[DatabaseConstants.colAngularSize] = enriched.angularSize;
          values[DatabaseConstants.colDescription] = enriched.description;
        }

        if (values.isEmpty) continue;

        await txn.update(
          DatabaseConstants.tableCelestialObjects,
          values,
          where: '${DatabaseConstants.colId} = ?',
          whereArgs: [object.id],
        );
      }
    });
  }
}
