import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/database_constants.dart';
import '../core/utils/catalog_reference_resolver.dart';
import '../core/utils/text_sanitizer.dart';

/// 동일 천체 그룹에서 대표 Catalog를 지정한다.
class CatalogPrimaryCatalogService {
  CatalogPrimaryCatalogService._();

  static const _equivalenceAsset = 'assets/catalog/catalog_equivalence.json';

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
    'solar': 99,
    'milky': 99,
  };

  static int _lastHiddenCount = 0;
  static int get lastHiddenCount => _lastHiddenCount;

  static Future<void> apply(Database db) async {
    final jsonGroups = await _loadEquivalenceGroups();

    await db.transaction((txn) async {
      final rows = await txn.query(DatabaseConstants.tableCelestialObjects);
      if (rows.isEmpty) {
        return;
      }

      final byId = {
        for (final row in rows)
          row[DatabaseConstants.colId] as String: Map<String, dynamic>.from(row),
      };

      for (final row in byId.values) {
        row[DatabaseConstants.colIsPrimaryCatalog] = 1;
        row[DatabaseConstants.colPrimaryCatalogId] = null;
      }

      var hiddenCount = 0;

      final groups = <_EquivalenceGroup>[
        ...jsonGroups,
        ..._discoverCrossCatalogGroups(byId),
      ];

      for (final group in groups) {
        hiddenCount += _applyGroup(group, byId);
      }

      for (final row in byId.values) {
        await txn.update(
          DatabaseConstants.tableCelestialObjects,
          {
            DatabaseConstants.colIsPrimaryCatalog:
                row[DatabaseConstants.colIsPrimaryCatalog],
            DatabaseConstants.colPrimaryCatalogId:
                row[DatabaseConstants.colPrimaryCatalogId],
            DatabaseConstants.colCrossCatalogRefsJson:
                row[DatabaseConstants.colCrossCatalogRefsJson],
            DatabaseConstants.colCommonName:
                row[DatabaseConstants.colCommonName],
          },
          where: '${DatabaseConstants.colId} = ?',
          whereArgs: [row[DatabaseConstants.colId]],
        );
      }

      await _ensurePrimaryIndex(txn);
      _lastHiddenCount = hiddenCount;
    });
  }

  static int _applyGroup(
    _EquivalenceGroup group,
    Map<String, Map<String, dynamic>> byId,
  ) {
    final members = group.members
        .where((id) => byId.containsKey(id))
        .toList(growable: false);
    if (members.length <= 1) {
      return 0;
    }

    final primaryId = _pickPrimaryId(
      members: members,
      canonicalId: group.canonicalId,
      byId: byId,
    );
    final primary = byId[primaryId];
    if (primary == null) {
      return 0;
    }

    final mergedCross = TextSanitizer.sanitizeList({
      ..._parseJsonList(
        primary[DatabaseConstants.colCrossCatalogRefsJson] as String?,
      ),
      ...members.where((id) => id != primaryId),
    });
    primary[DatabaseConstants.colCrossCatalogRefsJson] =
        mergedCross.isEmpty ? null : jsonEncode(mergedCross.toList());

    final commonName = TextSanitizer.sanitizeOptional(group.commonName);
    final primaryCommon =
        primary[DatabaseConstants.colCommonName] as String?;
    if (commonName != null &&
        _needsBetterCommonName(primaryCommon, primaryId)) {
      primary[DatabaseConstants.colCommonName] = commonName;
    } else {
      final bestCommonName = _bestCommonName(members, byId);
      if (bestCommonName != null &&
          _needsBetterCommonName(primaryCommon, primaryId)) {
        primary[DatabaseConstants.colCommonName] = bestCommonName;
      }
    }

    var hidden = 0;
    for (final memberId in members) {
      if (memberId == primaryId) {
        primary[DatabaseConstants.colIsPrimaryCatalog] = 1;
        primary[DatabaseConstants.colPrimaryCatalogId] = null;
        continue;
      }
      final member = byId[memberId];
      if (member == null) continue;
      member[DatabaseConstants.colIsPrimaryCatalog] = 0;
      member[DatabaseConstants.colPrimaryCatalogId] = primaryId;
      hidden++;
    }
    return hidden;
  }

  static List<_EquivalenceGroup> _discoverCrossCatalogGroups(
    Map<String, Map<String, dynamic>> byId,
  ) {
    final lookup = CatalogReferenceResolver.buildLookup(byId.keys);
    final edges = <String, Set<String>>{};

    for (final entry in byId.entries) {
      final objectId = entry.key;
      final row = entry.value;
      final refs = <String>{
        ..._parseJsonList(row[DatabaseConstants.colAliasesJson] as String?),
        ..._parseJsonList(
          row[DatabaseConstants.colCrossCatalogRefsJson] as String?,
        ),
      };

      for (final ref in refs) {
        final targetId = CatalogReferenceResolver.resolve(ref, lookup);
        if (targetId == null || targetId == objectId) {
          continue;
        }
        edges.putIfAbsent(objectId, () => <String>{}).add(targetId);
      }
    }

    final pairs = <(String, String)>[];
    for (final entry in edges.entries) {
      final objectId = entry.key;
      final source = byId[objectId];
      if (source == null) {
        continue;
      }
      final catalog = source[DatabaseConstants.colCatalog] as String?;
      if (catalog == null) {
        continue;
      }
      for (final targetId in entry.value) {
        final target = byId[targetId];
        if (target == null) {
          continue;
        }
        final targetCatalog = target[DatabaseConstants.colCatalog] as String?;
        if (targetCatalog == null || catalog == targetCatalog) {
          continue;
        }
        // 한쪽만 참조하는 경우 edges[targetId]가 없을 수 있다.
        if (!(edges[targetId]?.contains(objectId) ?? false)) {
          continue;
        }
        final pair = objectId.compareTo(targetId) < 0
            ? (objectId, targetId)
            : (targetId, objectId);
        if (!pairs.contains(pair)) {
          pairs.add(pair);
        }
      }
    }

    final parent = <String, String>{for (final id in byId.keys) id: id};

    String find(String id) {
      var current = id;
      while (parent[current] != current) {
        parent[current] = parent[parent[current]!]!;
        current = parent[current]!;
      }
      return current;
    }

    void union(String a, String b) {
      final rootA = find(a);
      final rootB = find(b);
      if (rootA != rootB) {
        parent[rootB] = rootA;
      }
    }

    for (final pair in pairs) {
      union(pair.$1, pair.$2);
    }

    final components = <String, Set<String>>{};
    for (final id in byId.keys) {
      components.putIfAbsent(find(id), () => <String>{}).add(id);
    }

    return components.values
        .where((members) => members.length > 1)
        .map(
          (members) {
            final memberList = members.toList()..sort();
            return _EquivalenceGroup(
              canonicalId: _pickPrimaryId(
                members: memberList,
                canonicalId: '',
                byId: byId,
              ),
              members: memberList,
              commonName: _bestCommonName(members, byId),
            );
          },
        )
        .toList(growable: false);
  }

  static String? _bestCommonName(
    Iterable<String> members,
    Map<String, Map<String, dynamic>> byId,
  ) {
    String? best;
    var bestScore = -1;

    for (final memberId in members) {
      final row = byId[memberId];
      if (row == null) continue;
      final commonName =
          TextSanitizer.sanitizeOptional(row[DatabaseConstants.colCommonName] as String?);
      if (commonName == null || _isGenericLabel(commonName)) {
        continue;
      }
      if (_labelsMatch(commonName, memberId)) {
        continue;
      }

      var score = 0;
      final catalog = row[DatabaseConstants.colCatalog] as String;
      score += (100 - (_catalogPriority[catalog] ?? 50)) * 10;
      score += row[DatabaseConstants.colIsFeatured] as int? ?? 0;
      if (commonName.contains(RegExp(r'[\uAC00-\uD7A3]'))) {
        score += 5;
      }
      if (score > bestScore) {
        bestScore = score;
        best = commonName;
      }
    }

    return best;
  }

  static bool _labelsMatch(String a, String b) {
    return CatalogReferenceResolver.normalizeKey(a) ==
        CatalogReferenceResolver.normalizeKey(b);
  }

  static Future<void> _ensurePrimaryIndex(Transaction txn) async {
    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_celestial_objects_primary
        ON ${DatabaseConstants.tableCelestialObjects}
        (${DatabaseConstants.colIsPrimaryCatalog})
    ''');
  }

  static Future<List<_EquivalenceGroup>> _loadEquivalenceGroups() async {
    try {
      final jsonString = await rootBundle.loadString(_equivalenceAsset);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final groups = data['groups'] as List<dynamic>? ?? const [];
      return groups
          .map(
            (group) =>
                _EquivalenceGroup.fromJson(group as Map<String, dynamic>),
          )
          .where((group) => group.members.length > 1)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String _pickPrimaryId({
    required List<String> members,
    required String canonicalId,
    required Map<String, Map<String, dynamic>> byId,
  }) {
    if (canonicalId.isNotEmpty && members.contains(canonicalId)) {
      return canonicalId;
    }

    final sorted = [...members]
      ..sort((a, b) {
        final rowA = byId[a]!;
        final rowB = byId[b]!;
        final priA =
            _catalogPriority[rowA[DatabaseConstants.colCatalog] as String] ??
                50;
        final priB =
            _catalogPriority[rowB[DatabaseConstants.colCatalog] as String] ??
                50;
        final priCompare = priA.compareTo(priB);
        if (priCompare != 0) {
          return priCompare;
        }

        final featuredA = rowA[DatabaseConstants.colIsFeatured] as int? ?? 0;
        final featuredB = rowB[DatabaseConstants.colIsFeatured] as int? ?? 0;
        final featuredCompare = featuredB.compareTo(featuredA);
        if (featuredCompare != 0) {
          return featuredCompare;
        }

        final displayA = rowA[DatabaseConstants.colDisplayPriority] as int? ??
            DatabaseConstants.defaultDisplayPriority;
        final displayB = rowB[DatabaseConstants.colDisplayPriority] as int? ??
            DatabaseConstants.defaultDisplayPriority;
        final displayCompare = displayA.compareTo(displayB);
        if (displayCompare != 0) {
          return displayCompare;
        }

        return a.compareTo(b);
      });

    return sorted.first;
  }

  static bool _needsBetterCommonName(String? current, String primaryId) {
    if (_isGenericLabel(current)) {
      return true;
    }
    if (current == null || current.trim().isEmpty) {
      return true;
    }
    // "NGC 2264"처럼 카탈로그 ID와 동일하면 표시용 통칭이 아니다.
    if (_labelsMatch(current, primaryId)) {
      return true;
    }
    return false;
  }

  static bool _isGenericLabel(String? value) {
    if (value == null || value.trim().isEmpty || value == '-') {
      return true;
    }
    const generic = {
      '발광성운',
      '반사성운',
      '암흑성운',
      '산개성단',
      '구상성단',
      '은하',
      '행성상성운',
      '초신성잔해',
      '기타',
      '성운',
      '성단',
    };
    return generic.contains(value.trim());
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

class _EquivalenceGroup {
  const _EquivalenceGroup({
    required this.canonicalId,
    required this.members,
    required this.commonName,
  });

  final String canonicalId;
  final List<String> members;
  final String? commonName;

  factory _EquivalenceGroup.fromJson(Map<String, dynamic> json) {
    final members = (json['members'] as List<dynamic>? ?? const [])
        .map((member) => member.toString())
        .toList(growable: false);
    return _EquivalenceGroup(
      canonicalId: json['canonicalId'] as String? ?? members.first,
      members: members,
      commonName: json['commonName'] as String?,
    );
  }
}
