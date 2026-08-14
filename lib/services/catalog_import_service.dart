import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/database_constants.dart';
import '../data/database/app_database.dart';
import 'catalog_dedup_service.dart';
import 'catalog_featured_ranking_service.dart';
import 'catalog_fts_service.dart';
import 'catalog_object_type_migration.dart';
import 'catalog_primary_catalog_service.dart';
import 'catalog_search_service.dart';
import 'catalog_seed_import_service.dart';

/// 번들 catalog_seed.db → SQLite 카탈로그 Upsert.
class CatalogImportService {
  CatalogImportService._();

  static Map<String, String>? _idRemap;
  static const _prefsKey = 'catalog_data_version';

  static Future<void> importAllIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_prefsKey) ?? 0;
    if (stored == DatabaseConstants.catalogDataVersion) {
      return;
    }

    await _loadIdRemap();
    await _remapShootingRecords();
    await _importCatalog();
    await prefs.setInt(_prefsKey, DatabaseConstants.catalogDataVersion);
  }

  static Future<void> _loadIdRemap() async {
    if (_idRemap != null) return;
    try {
      final jsonString = await rootBundle.loadString(
        'assets/catalog/id_remap.json',
      );
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      _idRemap = map.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      _idRemap = {};
    }
  }

  static Future<void> _remapShootingRecords() async {
    final db = await AppDatabase.instance;
    final remap = _idRemap ?? {};
    if (remap.isEmpty) return;

    await _remapShootingRecordsInDb(db, remap);
  }

  static Future<void> _remapShootingRecordsInDb(
    Database db,
    Map<String, String> remap,
  ) async {
    await db.transaction((txn) async {
      for (final entry in remap.entries) {
        await txn.update(
          DatabaseConstants.tableShootingRecords,
          {DatabaseConstants.colCelestialObjectId: entry.value},
          where: '${DatabaseConstants.colCelestialObjectId} = ?',
          whereArgs: [entry.key],
        );
      }
    });
  }

  @visibleForTesting
  static Future<void> remapShootingRecordsForTesting(
    Database db,
    Map<String, String> remap,
  ) => _remapShootingRecordsInDb(db, remap);

  static Future<void> _importCatalog() async {
    final db = await AppDatabase.instance;
    await CatalogSeedImportService.importFromSeed(db);
    // Upsert는 삭제를 하지 않으므로 암흑성운·재분류를 한 번 더 적용한다.
    await CatalogObjectTypeMigration.apply(
      db,
      globalAliases: CatalogSearchService.globalAliases,
      globalCrossCatalog: CatalogSearchService.globalCrossCatalog,
    );
    await CatalogDedupService.deduplicate(db);
    await CatalogPrimaryCatalogService.apply(db);
    await CatalogFeaturedRankingService.apply(db);
    await CatalogFtsService.rebuild(
      db,
      globalAliases: CatalogSearchService.globalAliases,
      globalCrossCatalog: CatalogSearchService.globalCrossCatalog,
    );
    CatalogSearchService.invalidateIndex();
    await CatalogSeedImportService.restoreCapturedFromShootingRecords(db);
  }
}
