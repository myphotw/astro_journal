import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/catalog_type.dart';
import '../core/constants/data_source.dart';
import '../core/constants/database_constants.dart';
import '../core/utils/text_sanitizer.dart';

/// 번들된 catalog_seed.db → 앱 DB Upsert (Delete 금지).
class CatalogSeedImportService {
  CatalogSeedImportService._();

  static const _seedAssetPath = 'assets/database/catalog_seed.db';

  static Future<void> importFromSeed(Database db) async {
    final seedPath = await _materializeSeedDb();
    final seedDb = await openDatabase(seedPath, readOnly: true);
    try {
      final rows = await seedDb.query(DatabaseConstants.tableCelestialObjects);
      await db.transaction((txn) async {
        for (final row in rows) {
          await _upsertRow(txn, _sanitizeRow(row));
        }
      });
    } finally {
      await seedDb.close();
    }
  }

  static Future<String> _materializeSeedDb() async {
    final bytes = await rootBundle.load(_seedAssetPath);
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'catalog_seed.db');
    final file = File(path);
    await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    return path;
  }

  static Map<String, dynamic> _sanitizeRow(Map<String, dynamic> row) {
    final sanitized = Map<String, dynamic>.from(row);

    for (final column in [
      DatabaseConstants.colName,
      DatabaseConstants.colCommonName,
      DatabaseConstants.colConstellation,
      DatabaseConstants.colDescription,
      DatabaseConstants.colType,
      DatabaseConstants.colObjectType,
    ]) {
      final value = sanitized[column];
      if (value is String) {
        sanitized[column] = TextSanitizer.sanitizeRequired(value);
      }
    }

    sanitized[DatabaseConstants.colSearchKeywords] =
        TextSanitizer.sanitizeSearchKeywords(
      sanitized[DatabaseConstants.colSearchKeywords] as String?,
    );

    sanitized[DatabaseConstants.colAliasesJson] = _sanitizeJsonListColumn(
      sanitized[DatabaseConstants.colAliasesJson] as String?,
    );
    sanitized[DatabaseConstants.colCrossCatalogRefsJson] =
        _sanitizeJsonListColumn(
      sanitized[DatabaseConstants.colCrossCatalogRefsJson] as String?,
    );

    return sanitized;
  }

  static String? _sanitizeJsonListColumn(String? raw) {
    final items = TextSanitizer.sanitizeList(_parseJsonList(raw));
    if (items.isEmpty) {
      return null;
    }
    return jsonEncode(items);
  }

  static Future<void> _upsertRow(
    DatabaseExecutor txn,
    Map<String, dynamic> seedRow,
  ) async {
    final catalog = seedRow[DatabaseConstants.colCatalog] as String?;
    if (catalog == null || CatalogType.tryFromValue(catalog) == null) {
      return;
    }

    final id = seedRow[DatabaseConstants.colId] as String;
    final existing = await txn.query(
      DatabaseConstants.tableCelestialObjects,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (existing.isEmpty) {
      await txn.insert(
        DatabaseConstants.tableCelestialObjects,
        seedRow,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return;
    }

    final current = existing.single;
    final updates = _buildMetadataUpdate(current, seedRow);
    if (updates.isEmpty) {
      return;
    }

    await txn.update(
      DatabaseConstants.tableCelestialObjects,
      updates,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
    );
  }

  static Map<String, dynamic> _buildMetadataUpdate(
    Map<String, dynamic> existing,
    Map<String, dynamic> seed,
  ) {
    final updates = <String, dynamic>{};

    void setIfPresent(String column) {
      if (!seed.containsKey(column)) {
        return;
      }
      final value = seed[column];
      if (value == null) {
        return;
      }
      if (value is String && value.trim().isEmpty) {
        return;
      }
      updates[column] = value;
    }

    for (final column in [
      DatabaseConstants.colName,
      DatabaseConstants.colCommonName,
      DatabaseConstants.colConstellation,
      DatabaseConstants.colRa,
      DatabaseConstants.colDec,
      DatabaseConstants.colMag,
      DatabaseConstants.colSearchKeywords,
      DatabaseConstants.colMajorAxis,
      DatabaseConstants.colMinorAxis,
      DatabaseConstants.colPositionAngle,
      DatabaseConstants.colAngularSize,
      DatabaseConstants.colDistanceLy,
      DatabaseConstants.colDescription,
      DatabaseConstants.colSeestarSupported,
      DatabaseConstants.colDataSource,
    ]) {
      setIfPresent(column);
    }

    final mergedAliases = _mergeJsonLists(
      existing[DatabaseConstants.colAliasesJson] as String?,
      seed[DatabaseConstants.colAliasesJson] as String?,
    );
    if (mergedAliases != null) {
      updates[DatabaseConstants.colAliasesJson] = mergedAliases;
    }

    final mergedCross = _mergeJsonLists(
      existing[DatabaseConstants.colCrossCatalogRefsJson] as String?,
      seed[DatabaseConstants.colCrossCatalogRefsJson] as String?,
    );
    if (mergedCross != null) {
      updates[DatabaseConstants.colCrossCatalogRefsJson] = mergedCross;
    }

    // 시드 재분류가 반영되도록 object_type은 항상 시드 값을 우선한다.
    final objectType = seed[DatabaseConstants.colObjectType] as String?;
    if (!_isBlank(objectType)) {
      updates[DatabaseConstants.colObjectType] = objectType;
      updates[DatabaseConstants.colType] = objectType;
    }

    if (updates[DatabaseConstants.colDataSource] == null &&
        seed[DatabaseConstants.colDataSource] == DataSource.seestar) {
      updates[DatabaseConstants.colDataSource] = DataSource.seestar;
    }

    return updates;
  }

  static String? _mergeJsonLists(String? existingRaw, String? seedRaw) {
    final existing = TextSanitizer.sanitizeList(_parseJsonList(existingRaw));
    final incoming = TextSanitizer.sanitizeList(_parseJsonList(seedRaw));
    if (incoming.isEmpty) {
      final sanitizedExisting =
          existing.isEmpty ? null : jsonEncode(existing);
      if (sanitizedExisting == existingRaw) {
        return null;
      }
      return sanitizedExisting;
    }

    final merged = TextSanitizer.sanitizeList([...existing, ...incoming]);
    if (merged.isEmpty) {
      return null;
    }
    final encoded = jsonEncode(merged);
    if (encoded == existingRaw) {
      return null;
    }
    return encoded;
  }

  static List<String> _parseJsonList(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final data = jsonDecode(raw);
      if (data is List) {
        return data.map((e) => e.toString()).toList();
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }

  static bool _isBlank(String? value) {
    if (value == null) {
      return true;
    }
    final text = value.trim();
    return text.isEmpty || text == '-';
  }

  /// 촬영 기록 기준 captured 플래그 복원 (기존 import와 동일).
  static Future<void> restoreCapturedFromShootingRecords(Database db) async {
    final records = await db.query(DatabaseConstants.tableShootingRecords);
    if (records.isEmpty) {
      return;
    }

    final latestByObject = <String, String>{};
    for (final row in records) {
      final objectId = row[DatabaseConstants.colCelestialObjectId] as String;
      final capturedAt = row[DatabaseConstants.colCapturedAt] as String;
      final prev = latestByObject[objectId];
      if (prev == null || capturedAt.compareTo(prev) > 0) {
        latestByObject[objectId] = capturedAt;
      }
    }

    for (final entry in latestByObject.entries) {
      await db.update(
        DatabaseConstants.tableCelestialObjects,
        {
          DatabaseConstants.colCaptured: 1,
          DatabaseConstants.colCapturedDate: entry.value,
        },
        where: '${DatabaseConstants.colId} = ?',
        whereArgs: [entry.key],
      );
    }
  }
}
