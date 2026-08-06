import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../core/constants/database_constants.dart';

/// Seestar 파생 메타데이터로 카테고리별 대표 천체(isFeatured)와
/// 표시 우선순위(displayPriority)를 하드코딩 없이 자동 계산한다.
///
/// Seestar StarDB가 갱신되어 seed 데이터가 바뀌면, import/migration 이후
/// 이 서비스가 다시 실행되어 최신 우선순위로 자동 갱신된다.
class CatalogFeaturedRankingService {
  CatalogFeaturedRankingService._();

  /// 일반 명칭(천체 유형 라벨) — 고유명이 아니므로 대표성 가점 대상에서 제외.
  static const Set<String> _genericNames = {
    '산개성단', '초신성잔해', '발광성운', '구상성단', '은하', '행성상성운',
    '기타', '반사성운', '행성', '성운+성단', '항성', '위성', '왜소행성',
    '쌍성', '복합성운', '성운', '성단', '은하단', '암흑성운', '성협',
  };

  /// Messier는 번호순을 유지하므로 랭킹 계산 대상에서 제외한다.
  static const String _messierCatalog = 'messier';

  /// 카탈로그별 대표 천체 개수 하한/상한.
  static const int _minFeaturedPerCatalog = 10;
  static const int _maxFeaturedPerCatalog = 50;
  static const double _featuredRatio = 0.1;

  /// 전체 celestial_objects에 대해 랭킹을 재계산하여 저장한다.
  static Future<void> apply(DatabaseExecutor db) async {
    final rows = await db.query(
      DatabaseConstants.tableCelestialObjects,
      columns: [
        DatabaseConstants.colId,
        DatabaseConstants.colCatalog,
        DatabaseConstants.colName,
        DatabaseConstants.colCommonName,
        DatabaseConstants.colObjectType,
        DatabaseConstants.colMag,
        DatabaseConstants.colAngularSize,
        DatabaseConstants.colDescription,
        DatabaseConstants.colAliasesJson,
        DatabaseConstants.colCrossCatalogRefsJson,
        DatabaseConstants.colSeestarSupported,
      ],
    );
    if (rows.isEmpty) {
      return;
    }

    final byCatalog = <String, List<_Scored>>{};
    for (final row in rows) {
      final catalog = row[DatabaseConstants.colCatalog] as String? ?? '';
      if (catalog == _messierCatalog) {
        continue;
      }
      final id = row[DatabaseConstants.colId] as String;
      final score = _score(row);
      final name = (row[DatabaseConstants.colName] as String? ?? '').trim();
      (byCatalog[catalog] ??= []).add(_Scored(id: id, score: score, name: name));
    }

    final updates = <String, ({bool featured, int priority})>{};
    for (final entry in byCatalog.entries) {
      final scored = entry.value
        ..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          if (byScore != 0) return byScore;
          return a.name.compareTo(b.name);
        });

      final featuredCount = scored.length <= _minFeaturedPerCatalog
          ? scored.length
          : math.min(
              _maxFeaturedPerCatalog,
              math.max(
                _minFeaturedPerCatalog,
                (scored.length * _featuredRatio).round(),
              ),
            );

      for (var i = 0; i < scored.length; i++) {
        updates[scored[i].id] = (
          featured: i < featuredCount,
          priority: i + 1,
        );
      }
    }

    if (updates.isEmpty) {
      return;
    }

    final batch = db.batch();
    updates.forEach((id, value) {
      batch.update(
        DatabaseConstants.tableCelestialObjects,
        {
          DatabaseConstants.colIsFeatured: value.featured ? 1 : 0,
          DatabaseConstants.colDisplayPriority: value.priority,
        },
        where: '${DatabaseConstants.colId} = ?',
        whereArgs: [id],
      );
    });
    await batch.commit(noResult: true);
  }

  static double _score(Map<String, Object?> row) {
    var score = 0.0;

    final commonName = row[DatabaseConstants.colCommonName] as String?;
    final objectType = row[DatabaseConstants.colObjectType] as String?;
    if (_isProperName(commonName, objectType)) {
      score += 45;
    }

    final aliasCount = _listLength(row[DatabaseConstants.colAliasesJson]) +
        _listLength(row[DatabaseConstants.colCrossCatalogRefsJson]);
    score += math.min(aliasCount, 6) * 4;

    final mag = _parseMagnitude(row[DatabaseConstants.colMag]);
    if (mag != null) {
      score += math.max(0.0, math.min(25.0, (15.0 - mag) / 15.0 * 25.0));
    }

    final size = _parseMaxSize(row[DatabaseConstants.colAngularSize]);
    if (size != null) {
      score += math.min(15.0, (math.log(size + 1) / math.ln10) * 12.0);
    }

    final description = row[DatabaseConstants.colDescription] as String?;
    if (description != null &&
        description.trim().isNotEmpty &&
        description.trim() != '-') {
      score += 6;
    }

    if ((row[DatabaseConstants.colSeestarSupported] as int? ?? 0) == 1) {
      score += 20;
    }

    return score;
  }

  static bool _isProperName(String? commonName, String? objectType) {
    if (commonName == null) {
      return false;
    }
    final cn = commonName.trim();
    if (cn.isEmpty || _genericNames.contains(cn)) {
      return false;
    }
    if (cn == (objectType ?? '').trim()) {
      return false;
    }
    // "IC 1318A", "NGC 1990" 처럼 카탈로그 식별자만 있는 경우는 고유명이 아님.
    if (RegExp(r'^(M|NGC|IC|C|Caldwell|Sh2-?|RCW|vdB|Barnard|B|LDN|LBN)\s*\d+[A-Za-z]?$',
            caseSensitive: false)
        .hasMatch(cn)) {
      return false;
    }
    return true;
  }

  static int _listLength(Object? rawJson) {
    if (rawJson is! String || rawJson.isEmpty) {
      return 0;
    }
    try {
      final data = jsonDecode(rawJson);
      if (data is List) {
        return data.length;
      }
    } catch (_) {
      return 0;
    }
    return 0;
  }

  static double? _parseMagnitude(Object? raw) {
    if (raw == null) return null;
    return double.tryParse(raw.toString());
  }

  static double? _parseMaxSize(Object? raw) {
    if (raw == null) return null;
    final matches = RegExp(r'[\d.]+').allMatches(raw.toString()).toList();
    if (matches.isEmpty) {
      return null;
    }
    double? best;
    for (final m in matches.take(2)) {
      final value = double.tryParse(m.group(0)!);
      if (value == null) continue;
      if (best == null || value > best) {
        best = value;
      }
    }
    return best;
  }
}

class _Scored {
  _Scored({required this.id, required this.score, required this.name});

  final String id;
  final double score;
  final String name;
}
