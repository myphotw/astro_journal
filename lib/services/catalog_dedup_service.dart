import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/constants/database_constants.dart';
import '../core/utils/text_sanitizer.dart';

/// 천체 DB 중복·미지원 카탈로그 정리.
class CatalogDedupService {
  CatalogDedupService._();

  static const _supportedCatalogs = {
    'messier',
    'ngc',
    'ic',
    'caldwell',
    'sh2',
    'rcw',
    'vdb',
    'star',
    'barnard',
    'ldn',
    'lbn',
    'solar',
    'milky',
  };

  static const _catalogPriority = {
    'messier': 0,
    'ngc': 1,
    'ic': 2,
    'caldwell': 3,
    'sh2': 4,
    'rcw': 5,
    'vdb': 6,
    'barnard': 7,
    'ldn': 8,
    'lbn': 9,
    'star': 10,
    'solar': 99,
    'milky': 99,
  };

  static Future<void> deduplicate(Database db) async {
    await db.transaction((txn) async {
      final rows = await txn.query(DatabaseConstants.tableCelestialObjects);
      if (rows.isEmpty) {
        return;
      }

      final objects = rows.map((row) => Map<String, dynamic>.from(row)).toList();
      final byId = {for (final row in objects) row[DatabaseConstants.colId] as String: row};
      final removedIds = <String>{};

      void removeId(String id) {
        if (!byId.containsKey(id)) {
          return;
        }
        removedIds.add(id);
        byId.remove(id);
      }

      // 1) 미지원 catalog 제거 (barnard/lbn/ldn 등 → messier 오인 방지)
      for (final row in byId.values.toList()) {
        final catalog = row[DatabaseConstants.colCatalog] as String;
        if (!_supportedCatalogs.contains(catalog)) {
          removeId(row[DatabaseConstants.colId] as String);
        }
      }

      // 2) catalog+num(+suffix) 중복 제거
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final row in byId.values) {
        final key = _groupKey(row);
        groups.putIfAbsent(key, () => []).add(row);
      }

      for (final group in groups.values) {
        if (group.length <= 1) {
          continue;
        }
        group.sort(_compareCanonical);
        final keep = group.first;
        for (var i = 1; i < group.length; i++) {
          _mergeInto(keep, group[i]);
          removeId(group[i][DatabaseConstants.colId] as String);
        }
      }

      // 3) 교차 카탈로그 중복 → 대표 Catalog 지정 (행 유지)
      final index = <String, Map<String, dynamic>>{};
      for (final row in byId.values) {
        index[_groupKey(row)] = row;
      }

      for (final row in byId.values.toList()) {
        row.putIfAbsent(DatabaseConstants.colIsPrimaryCatalog, () => 1);
        row.putIfAbsent(DatabaseConstants.colPrimaryCatalogId, () => null);
        final pri = _catalogPriority[row[DatabaseConstants.colCatalog] as String] ?? 50;
        final refs = _collectRefs(row);
        final secondaryIds = <String>[];

        for (final ref in refs) {
          final ngc = RegExp(r'NGC\s*(\d+)', caseSensitive: false).firstMatch(ref);
          if (ngc != null && pri < _catalogPriority['ngc']!) {
            final target = index[_groupKeyFor('ngc', int.parse(ngc.group(1)!))];
            if (target != null && target[DatabaseConstants.colId] != row[DatabaseConstants.colId]) {
              secondaryIds.add(target[DatabaseConstants.colId] as String);
            }
          }

          final ic = RegExp(r'IC\s*(\d+)', caseSensitive: false).firstMatch(ref);
          if (ic != null && pri < _catalogPriority['ic']!) {
            final suffix = _icSuffix(ref, ic.end);
            final target = index[_groupKeyFor('ic', int.parse(ic.group(1)!), suffix: suffix)];
            if (target != null && target[DatabaseConstants.colId] != row[DatabaseConstants.colId]) {
              secondaryIds.add(target[DatabaseConstants.colId] as String);
            }
          }

          final messier = RegExp(r'\bM(\d+)\b', caseSensitive: false).firstMatch(ref);
          if (messier != null && pri < _catalogPriority['messier']!) {
            final target = index[_groupKeyFor('messier', int.parse(messier.group(1)!))];
            if (target != null && target[DatabaseConstants.colId] != row[DatabaseConstants.colId]) {
              secondaryIds.add(target[DatabaseConstants.colId] as String);
            }
          }
        }

        for (final secondaryId in secondaryIds.toSet()) {
          final secondary = byId[secondaryId];
          if (secondary == null) {
            continue;
          }
          _mergeInto(row, secondary);
          secondary[DatabaseConstants.colIsPrimaryCatalog] = 0;
          secondary[DatabaseConstants.colPrimaryCatalogId] =
              row[DatabaseConstants.colId] as String;
          row[DatabaseConstants.colIsPrimaryCatalog] = 1;
          row[DatabaseConstants.colPrimaryCatalogId] = null;
        }
      }

      // shooting_records celestial_object_id 리맵
      if (removedIds.isNotEmpty) {
        for (final removedId in removedIds) {
          final replacement = _findReplacementId(removedId, byId.values);
          if (replacement == null) {
            continue;
          }
          await txn.update(
            DatabaseConstants.tableShootingRecords,
            {DatabaseConstants.colCelestialObjectId: replacement},
            where: '${DatabaseConstants.colCelestialObjectId} = ?',
            whereArgs: [removedId],
          );
        }

        await txn.delete(
          DatabaseConstants.tableCelestialObjects,
          where:
              '${DatabaseConstants.colId} IN (${List.filled(removedIds.length, '?').join(', ')})',
          whereArgs: removedIds.toList(),
        );
      }

      for (final row in byId.values) {
        await txn.update(
          DatabaseConstants.tableCelestialObjects,
          row,
          where: '${DatabaseConstants.colId} = ?',
          whereArgs: [row[DatabaseConstants.colId]],
        );
      }
    });
  }

  static String? _findReplacementId(
    String removedId,
    Iterable<Map<String, dynamic>> remaining,
  ) {
    for (final row in remaining) {
      final cross = _parseJsonList(row[DatabaseConstants.colCrossCatalogRefsJson] as String?);
      final aliases = _parseJsonList(row[DatabaseConstants.colAliasesJson] as String?);
      if (cross.contains(removedId) || aliases.contains(removedId)) {
        return row[DatabaseConstants.colId] as String;
      }
    }
    return remaining.isNotEmpty ? remaining.first[DatabaseConstants.colId] as String : null;
  }

  static String _groupKey(Map<String, dynamic> row) =>
      _groupKeyFor(
        row[DatabaseConstants.colCatalog] as String,
        row[DatabaseConstants.colNum] as int,
        suffix: row[DatabaseConstants.colSuffix] as String?,
      );

  static String _groupKeyFor(
    String catalog,
    int num, {
    String? suffix,
  }) =>
      '$catalog|$num|${suffix ?? ''}';

  static int _compareCanonical(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final expectedA = _expectedId(a);
    final expectedB = _expectedId(b);
    final priA = _catalogPriority[a[DatabaseConstants.colCatalog] as String] ?? 50;
    final priB = _catalogPriority[b[DatabaseConstants.colCatalog] as String] ?? 50;
    final idA = a[DatabaseConstants.colId] as String;
    final idB = b[DatabaseConstants.colId] as String;

    int score(Map<String, dynamic> row, String id, String expected, int pri) {
      var value = pri * 10;
      if (id == expected) {
        value -= 5;
      }
      if (row[DatabaseConstants.colDataSource] != 'Seestar') {
        value -= 1;
      }
      return value;
    }

    return score(a, idA, expectedA, priA).compareTo(score(b, idB, expectedB, priB));
  }

  static String _expectedId(Map<String, dynamic> row) {
    final catalog = row[DatabaseConstants.colCatalog] as String;
    final num = row[DatabaseConstants.colNum] as int;
    final suffix = row[DatabaseConstants.colSuffix] as String? ?? '';
    switch (catalog) {
      case 'messier':
        return 'M$num';
      case 'ngc':
        return 'NGC$num';
      case 'ic':
        return 'IC$num$suffix';
      case 'caldwell':
        return 'C$num';
      case 'sh2':
        return 'Sh2-$num';
      case 'rcw':
        return 'RCW$num';
      case 'vdb':
        return 'vdB$num';
      case 'barnard':
        return 'B$num';
      case 'ldn':
        return 'LDN$num';
      case 'lbn':
        return 'LBN$num';
      case 'solar':
        return 'solar_$num';
      case 'milky':
        return 'mw';
      default:
        return row[DatabaseConstants.colId] as String;
    }
  }

  static List<String> _collectRefs(Map<String, dynamic> row) {
    final refs = <String>[
      ..._parseJsonList(row[DatabaseConstants.colAliasesJson] as String?),
      ..._parseJsonList(row[DatabaseConstants.colCrossCatalogRefsJson] as String?),
    ];
    final keywords = row[DatabaseConstants.colSearchKeywords] as String?;
    if (keywords != null && keywords.isNotEmpty) {
      refs.addAll(keywords.split('|'));
    }
    return refs;
  }

  static String _icSuffix(String ref, int end) {
    final tail = ref.substring(end).trim().toUpperCase();
    if (tail.startsWith('A')) {
      return 'A';
    }
    if (tail.startsWith('B')) {
      return 'B';
    }
    return '';
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

  static void _mergeInto(
    Map<String, dynamic> keep,
    Map<String, dynamic> drop,
  ) {
    for (final column in [
      DatabaseConstants.colDescription,
      DatabaseConstants.colAngularSize,
      DatabaseConstants.colSearchKeywords,
      DatabaseConstants.colMajorAxis,
      DatabaseConstants.colMinorAxis,
      DatabaseConstants.colPositionAngle,
      DatabaseConstants.colCommonName,
    ]) {
      final current = keep[column];
      final incoming = drop[column];
      if ((current == null || '$current'.trim().isEmpty || current == '-') &&
          incoming != null &&
          '$incoming'.trim().isNotEmpty) {
        keep[column] = incoming;
      }
    }

    final aliases = TextSanitizer.sanitizeList({
      ..._parseJsonList(keep[DatabaseConstants.colAliasesJson] as String?),
      ..._parseJsonList(drop[DatabaseConstants.colAliasesJson] as String?),
    });
    final cross = TextSanitizer.sanitizeList({
      ..._parseJsonList(keep[DatabaseConstants.colCrossCatalogRefsJson] as String?),
      ..._parseJsonList(drop[DatabaseConstants.colCrossCatalogRefsJson] as String?),
      drop[DatabaseConstants.colId] as String,
    });
    keep[DatabaseConstants.colAliasesJson] =
        aliases.isEmpty ? null : jsonEncode(aliases.toList());
    keep[DatabaseConstants.colCrossCatalogRefsJson] =
        cross.isEmpty ? null : jsonEncode(cross.toList());
  }
}
