import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/constants/database_constants.dart';
import '../core/utils/text_sanitizer.dart';

/// 기존 celestial_objects 행에서 한자(CJK)를 제거한다.
class CatalogHanziCleanupMigration {
  CatalogHanziCleanupMigration._();

  static Future<void> cleanup(Database db) async {
    final rows = await db.query(DatabaseConstants.tableCelestialObjects);
    if (rows.isEmpty) {
      return;
    }

    await db.transaction((txn) async {
      for (final row in rows) {
        final updates = _buildSanitizedUpdates(row);
        if (updates.isEmpty) {
          continue;
        }
        await txn.update(
          DatabaseConstants.tableCelestialObjects,
          updates,
          where: '${DatabaseConstants.colId} = ?',
          whereArgs: [row[DatabaseConstants.colId]],
        );
      }
    });
  }

  static Map<String, dynamic> _buildSanitizedUpdates(
    Map<String, dynamic> row,
  ) {
    final updates = <String, dynamic>{};

    void setText(String column, String? sanitized) {
      final current = row[column];
      if (current == sanitized) {
        return;
      }
      if (current == null && sanitized == null) {
        return;
      }
      updates[column] = sanitized;
    }

    setText(
      DatabaseConstants.colName,
      TextSanitizer.sanitizeRequired(row[DatabaseConstants.colName] as String?),
    );
    setText(
      DatabaseConstants.colCommonName,
      TextSanitizer.sanitizeOptional(
        row[DatabaseConstants.colCommonName] as String?,
      ),
    );
    setText(
      DatabaseConstants.colType,
      TextSanitizer.sanitizeRequired(row[DatabaseConstants.colType] as String?),
    );
    setText(
      DatabaseConstants.colObjectType,
      TextSanitizer.sanitizeOptional(
        row[DatabaseConstants.colObjectType] as String?,
      ),
    );
    setText(
      DatabaseConstants.colConstellation,
      TextSanitizer.sanitizeRequired(
        row[DatabaseConstants.colConstellation] as String?,
      ),
    );
    setText(
      DatabaseConstants.colDescription,
      TextSanitizer.sanitizeOptional(
        row[DatabaseConstants.colDescription] as String?,
      ),
    );
    setText(
      DatabaseConstants.colBestSeason,
      TextSanitizer.sanitizeOptional(
        row[DatabaseConstants.colBestSeason] as String?,
      ),
    );
    setText(
      DatabaseConstants.colAngularSize,
      TextSanitizer.sanitizeOptional(
        row[DatabaseConstants.colAngularSize] as String?,
      ),
    );
    setText(
      DatabaseConstants.colSearchKeywords,
      TextSanitizer.sanitizeSearchKeywords(
        row[DatabaseConstants.colSearchKeywords] as String?,
      ),
    );
    setText(
      DatabaseConstants.colMemo,
      _sanitizeMemo(row[DatabaseConstants.colMemo] as String?),
    );

    setText(
      DatabaseConstants.colAliasesJson,
      _sanitizeJsonListColumn(row[DatabaseConstants.colAliasesJson] as String?),
    );
    setText(
      DatabaseConstants.colCrossCatalogRefsJson,
      _sanitizeJsonListColumn(
        row[DatabaseConstants.colCrossCatalogRefsJson] as String?,
      ),
    );
    setText(
      DatabaseConstants.colTagsJson,
      _sanitizeJsonListColumn(row[DatabaseConstants.colTagsJson] as String?),
    );

    return updates;
  }

  static String? _sanitizeMemo(String? value) {
    if (value == null || value.isEmpty) {
      return value;
    }
    return TextSanitizer.stripHanzi(value);
  }

  static String? _sanitizeJsonListColumn(String? raw) {
    final items = TextSanitizer.sanitizeList(_parseJsonList(raw));
    if (items.isEmpty) {
      return raw == null || raw.isEmpty ? raw : null;
    }
    return jsonEncode(items);
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
}
