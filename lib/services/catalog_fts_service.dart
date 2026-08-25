import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/constants/catalog_type.dart';
import '../core/constants/constellation_names.dart';
import '../core/constants/database_constants.dart';
import '../core/policies/catalog_deletion_policy.dart';
import '../data/models/catalog_object.dart';

/// SQLite FTS5 기반 카탈로그 검색.
abstract final class CatalogFtsService {
  static const _table = DatabaseConstants.tableCelestialObjectsFts;
  static const _colObjectId = DatabaseConstants.colFtsObjectId;
  static const _colSearchText = DatabaseConstants.colFtsSearchText;

  static Future<void> ensureSchema(Database db) async {
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS $_table USING fts5(
        $_colObjectId UNINDEXED,
        $_colSearchText,
        tokenize = 'unicode61 remove_diacritics 0'
      )
    ''');
  }

  static Future<void> rebuild(
    Database db, {
    Map<String, List<String>> globalAliases = const {},
    Map<String, List<String>> globalCrossCatalog = const {},
  }) async {
    await ensureSchema(db);
    await db.execute('DELETE FROM $_table');

    final rows = await db.query(
      DatabaseConstants.tableCelestialObjects,
      columns: [
        DatabaseConstants.colId,
        DatabaseConstants.colCatalog,
        DatabaseConstants.colNum,
        DatabaseConstants.colSuffix,
        DatabaseConstants.colName,
        DatabaseConstants.colCommonName,
        DatabaseConstants.colType,
        DatabaseConstants.colObjectType,
        DatabaseConstants.colConstellation,
        DatabaseConstants.colSearchKeywords,
        DatabaseConstants.colAliasesJson,
        DatabaseConstants.colCrossCatalogRefsJson,
        DatabaseConstants.colTagsJson,
      ],
    );

    if (rows.isEmpty) {
      return;
    }

    final batch = db.batch();
    for (final row in rows) {
      if (CatalogDeletionPolicy.isDeleted(
        _parseJsonList(row[DatabaseConstants.colTagsJson] as String?),
      )) {
        continue;
      }
      final objectId = row[DatabaseConstants.colId] as String;
      final searchText = _composeSearchText(
        row,
        globalAliases: globalAliases,
        globalCrossCatalog: globalCrossCatalog,
      );
      batch.insert(_table, {
        _colObjectId: objectId,
        _colSearchText: searchText,
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<void> removeObject(Database db, String objectId) async {
    await ensureSchema(db);
    await db.delete(_table, where: '$_colObjectId = ?', whereArgs: [objectId]);
  }

  static Future<List<String>> searchObjectIds(
    Database db,
    String query, {
    int limit = 50,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) {
      return const [];
    }

    final designationIds = await _lookupDesignationIds(db, trimmed);
    if (designationIds.isNotEmpty) {
      return designationIds.take(limit).toList(growable: false);
    }

    final ftsQuery = _toFtsQuery(trimmed);
    if (ftsQuery == null) {
      return const [];
    }

    try {
      // 텍스트 관련도(bm25)가 비슷할 때는 대표 천체를 먼저 노출한다.
      final rows = await db.rawQuery(
        '''
        SELECT f.object_id AS object_id
        FROM (
          SELECT $_colObjectId AS object_id, bm25($_table) AS text_rank
          FROM $_table
          WHERE $_colSearchText MATCH ?
        ) AS f
        JOIN ${DatabaseConstants.tableCelestialObjects} AS c
          ON c.${DatabaseConstants.colId} = f.object_id
        ORDER BY f.text_rank,
          c.${DatabaseConstants.colIsFeatured} DESC,
          c.${DatabaseConstants.colDisplayPriority} ASC
        LIMIT ?
        ''',
        [ftsQuery, limit],
      );
      return rows
          .map((row) => row['object_id'] as String)
          .toList(growable: false);
    } on DatabaseException {
      return const [];
    }
  }

  static String _composeSearchText(
    Map<String, Object?> row, {
    required Map<String, List<String>> globalAliases,
    required Map<String, List<String>> globalCrossCatalog,
  }) {
    final id = row[DatabaseConstants.colId] as String;
    final catalog = row[DatabaseConstants.colCatalog] as String;
    final num = row[DatabaseConstants.colNum] as int;
    final suffix = row[DatabaseConstants.colSuffix] as String?;
    final catalogType = CatalogType.tryFromValue(catalog);
    final displayName = catalogType == null
        ? id
        : CatalogObject(
            id: id,
            number: num,
            catalog: catalogType,
            name: row[DatabaseConstants.colName] as String? ?? id,
            type: row[DatabaseConstants.colType] as String? ?? '-',
            constellation:
                row[DatabaseConstants.colConstellation] as String? ?? '-',
            ra: '-',
            dec: '-',
            magnitude: '-',
            suffix: suffix,
          ).displayName;

    final parts = <String>[
      id,
      displayName,
      row[DatabaseConstants.colName] as String? ?? '',
      row[DatabaseConstants.colCommonName] as String? ?? '',
      row[DatabaseConstants.colType] as String? ?? '',
      row[DatabaseConstants.colObjectType] as String? ?? '',
      row[DatabaseConstants.colConstellation] as String? ?? '',
      ConstellationNames.normalize(
        row[DatabaseConstants.colConstellation] as String?,
      ),
      row[DatabaseConstants.colSearchKeywords] as String? ?? '',
      ..._parseJsonList(row[DatabaseConstants.colAliasesJson] as String?),
      ..._parseJsonList(row[DatabaseConstants.colCrossCatalogRefsJson] as String?),
      ..._parseJsonList(row[DatabaseConstants.colTagsJson] as String?),
      ...?globalAliases[id],
      ...?globalCrossCatalog[id],
      ...ConstellationNames.searchTerms(
        row[DatabaseConstants.colConstellation] as String?,
      ),
    ];

    return parts
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != '-')
        .join(' ');
  }

  static List<String> _parseJsonList(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final data = jsonDecode(raw);
      if (data is List) {
        return data.map((item) => item.toString()).toList(growable: false);
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }

  static String? _toFtsQuery(String query) {
    final tokens = query
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return null;
    }

    return tokens
        .map((token) {
          final escaped = token.replaceAll('"', '""');
          return '"$escaped"*';
        })
        .join(' ');
  }

  static Future<List<String>> _lookupDesignationIds(
    Database db,
    String query,
  ) async {
    final normalized =
        query.replaceAll(RegExp(r'[\s\-_]+'), '').toUpperCase();

    final messier = RegExp(r'^M(\d+)$').firstMatch(normalized);
    if (messier != null) {
      return _idsByCatalogNumber(
        db,
        catalog: CatalogType.messier,
        number: int.parse(messier.group(1)!),
      );
    }

    final ngc = RegExp(r'^NGC(\d+)$').firstMatch(normalized);
    if (ngc != null) {
      return _idsByCatalogNumber(
        db,
        catalog: CatalogType.ngc,
        number: int.parse(ngc.group(1)!),
      );
    }

    final ic = RegExp(r'^IC(\d+)([AB])?$').firstMatch(normalized);
    if (ic != null) {
      return _idsByCatalogNumber(
        db,
        catalog: CatalogType.ic,
        number: int.parse(ic.group(1)!),
        suffix: ic.group(2),
      );
    }

    final caldwellShort = RegExp(r'^C(\d+)$').firstMatch(normalized);
    final caldwellLong = RegExp(r'^CALDWELL(\d+)$').firstMatch(normalized);
    final caldwellNumber =
        caldwellShort?.group(1) ?? caldwellLong?.group(1);
    if (caldwellNumber != null) {
      return _idsByCatalogNumber(
        db,
        catalog: CatalogType.caldwell,
        number: int.parse(caldwellNumber),
      );
    }

    final sh2 = RegExp(r'^SH2(\d+)$').firstMatch(normalized);
    if (sh2 != null) {
      return _idsByCatalogNumber(
        db,
        catalog: CatalogType.sh2,
        number: int.parse(sh2.group(1)!),
      );
    }

    final rcw = RegExp(r'^RCW(\d+)$').firstMatch(normalized);
    if (rcw != null) {
      return _idsByCatalogNumber(
        db,
        catalog: CatalogType.rcw,
        number: int.parse(rcw.group(1)!),
      );
    }

    final vdb = RegExp(r'^VDB(\d+)$').firstMatch(normalized);
    if (vdb != null) {
      return _idsByCatalogNumber(
        db,
        catalog: CatalogType.vdb,
        number: int.parse(vdb.group(1)!),
      );
    }

    final barnard = RegExp(r'^(?:BARNARD|B)(\d+)$').firstMatch(normalized);
    if (barnard != null) {
      return _idsByCatalogNumber(
        db,
        catalog: CatalogType.barnard,
        number: int.parse(barnard.group(1)!),
      );
    }

    final ldn = RegExp(r'^LDN(\d+)$').firstMatch(normalized);
    if (ldn != null) {
      return _idsByCatalogNumber(
        db,
        catalog: CatalogType.ldn,
        number: int.parse(ldn.group(1)!),
      );
    }

    final lbn = RegExp(r'^LBN(\d+)$').firstMatch(normalized);
    if (lbn != null) {
      return _idsByCatalogNumber(
        db,
        catalog: CatalogType.lbn,
        number: int.parse(lbn.group(1)!),
      );
    }

    return const [];
  }

  static Future<List<String>> _idsByCatalogNumber(
    Database db, {
    required CatalogType catalog,
    required int number,
    String? suffix,
  }) async {
    final rows = await db.query(
      DatabaseConstants.tableCelestialObjects,
      columns: [DatabaseConstants.colId, DatabaseConstants.colSuffix],
      where: suffix == null
          ? '${DatabaseConstants.colCatalog} = ? AND ${DatabaseConstants.colNum} = ?'
          : '${DatabaseConstants.colCatalog} = ? AND ${DatabaseConstants.colNum} = ? AND ${DatabaseConstants.colSuffix} = ?',
      whereArgs: suffix == null
          ? [catalog.value, number]
          : [catalog.value, number, suffix],
      limit: 5,
    );

    if (suffix == null && rows.length > 1) {
      for (final row in rows) {
        final value = row[DatabaseConstants.colSuffix] as String?;
        if (value == null || value.isEmpty) {
          return [row[DatabaseConstants.colId] as String];
        }
      }
    }

    return rows.map((row) => row[DatabaseConstants.colId] as String).toList();
  }
}
