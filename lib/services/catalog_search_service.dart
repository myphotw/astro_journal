import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/constants/catalog_type.dart';
import '../core/utils/text_sanitizer.dart';
import '../data/models/catalog_object.dart';
import 'catalog_search_index.dart';

/// 카탈로그 검색 및 분석된 대상명으로 천체를 자동 매칭한다.
class CatalogSearchService {
  CatalogSearchService();

  static Map<String, List<String>> _globalAliases = {};
  static Map<String, List<String>> _globalCrossCatalog = {};
  static bool _searchMapsLoaded = false;

  /// 앱 시작 시 search alias / cross-catalog JSON을 로드한다.
  static Future<void> loadGlobalAliases() async {
    if (_searchMapsLoaded) return;
    _globalAliases = await _loadStringListMap('assets/catalog/search_aliases.json');
    _globalCrossCatalog =
        await _loadStringListMap('assets/catalog/search_cross_catalog.json');
    _searchMapsLoaded = true;
  }

  static Future<Map<String, List<String>>> _loadStringListMap(
    String assetPath,
  ) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return map.map(
        (key, value) => MapEntry(
          key,
          TextSanitizer.sanitizeList(
            (value as List<dynamic>).map((e) => e as String),
          ),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  static Map<String, List<String>> get globalAliases => _globalAliases;
  static Map<String, List<String>> get globalCrossCatalog => _globalCrossCatalog;

  /// 검색 인덱스를 미리 빌드한다 (UI 진입 직 호출 권장).
  void ensureIndex(List<CatalogObject> allObjects) {
    if (_cachedIndex != null &&
        _cachedIndex!.length == allObjects.length &&
        _cachedPrimaryById != null) {
      return;
    }
    _cachedIndex = CatalogSearchIndex.build(
      allObjects,
      globalAliases: _globalAliases,
      globalCrossCatalog: _globalCrossCatalog,
    );
    _cachedPrimaryById = {
      for (final object in allObjects)
        if (object.isPrimaryCatalog) object.id: object,
    };
  }

  /// CatalogViewModel 등에서 이미 만든 인덱스를 서비스 캐시에 공유한다.
  static void adoptIndex(
    CatalogSearchIndex index,
    List<CatalogObject> allObjects,
  ) {
    _cachedIndex = index;
    _cachedPrimaryById = {
      for (final object in allObjects)
        if (object.isPrimaryCatalog) object.id: object,
    };
  }

  /// displayName, commonName, 별칭, 유형, 별자리로 전체 카탈로그를 검색한다.
  List<CatalogObject> search(
    String query,
    List<CatalogObject> allObjects, {
    CatalogSearchIndex? index,
  }) {
    if (query.trim().isEmpty) return [];

    if (index == null) {
      ensureIndex(allObjects);
    }

    final resolvedIndex = index ?? _cachedIndex!;

    return mapToPrimaryCatalogResults(
      resolvedIndex.search(query),
      allObjects,
    );
  }

  /// 검색 히트를 카탈로그 목록(대표 천체)만 남기고 중복을 제거한다.
  static List<CatalogObject> mapToPrimaryCatalogResults(
    List<CatalogObject> hits,
    List<CatalogObject> allObjects,
  ) {
    final primaryById = _cachedPrimaryById ??
        {
          for (final object in allObjects)
            if (object.isPrimaryCatalog) object.id: object,
        };

    final seen = <String>{};
    final mapped = <CatalogObject>[];

    for (final hit in hits) {
      final resolved = resolvePrimaryFromList(hit, allObjects);
      final canonical = primaryById[resolved.id];
      if (canonical == null) {
        continue;
      }
      if (seen.add(canonical.id)) {
        mapped.add(canonical);
      }
    }

    return mapped;
  }

  static CatalogSearchIndex? _cachedIndex;
  static Map<String, CatalogObject>? _cachedPrimaryById;

  static void invalidateIndex() {
    _cachedIndex = null;
    _cachedPrimaryById = null;
  }

  /// 비대표 Catalog 검색 결과를 대표 Catalog로 변환한다.
  static CatalogObject resolvePrimaryFromList(
    CatalogObject object,
    List<CatalogObject> allObjects,
  ) {
    if (object.isPrimaryCatalog) {
      return object;
    }
    final primaryId = object.effectivePrimaryId;
    final cached = _cachedPrimaryById?[primaryId];
    if (cached != null) {
      return cached;
    }
    for (final candidate in allObjects) {
      if (candidate.id == primaryId) {
        return candidate;
      }
    }
    return object;
  }

  /// 분석된 대상명으로 카탈로그 항목을 자동 선택한다.
  CatalogObject? resolveTarget(String? targetName, List<CatalogObject> all) {
    if (targetName == null || targetName.trim().isEmpty) return null;

    final normalized = _normalize(targetName);

    for (final resolver in _resolvers) {
      final match = resolver.resolve(normalized, all);
      if (match != null) {
        return resolvePrimaryFromList(match, all);
      }
    }

    for (final obj in all) {
      if (_normalize(obj.displayName) == normalized) {
        return resolvePrimaryFromList(obj, all);
      }
      if (_normalize(obj.displayCommonName) == normalized) {
        return resolvePrimaryFromList(obj, all);
      }
      if (_normalize(obj.name) == normalized) {
        return resolvePrimaryFromList(obj, all);
      }
      for (final alias in _allSearchTerms(obj)) {
        if (_normalize(alias) == normalized) {
          return resolvePrimaryFromList(obj, all);
        }
      }
    }

    final results = search(targetName, all);
    if (results.length == 1) return results.first;

    return null;
  }

  List<String> _allSearchTerms(CatalogObject obj) {
    final merged = <String>[
      ...obj.aliases,
      ...obj.crossCatalogRefs,
      ...?_globalAliases[obj.id],
      ...?_globalCrossCatalog[obj.id],
    ];
    return merged.toSet().toList();
  }

  String _normalize(String input) =>
      input.replaceAll(RegExp(r'[\s\-_]+'), '').toUpperCase();
}

abstract class _CatalogTargetResolver {
  CatalogObject? resolve(String normalized, List<CatalogObject> all);
}

class _MessierResolver implements _CatalogTargetResolver {
  static final _pattern = RegExp(r'^M(\d+)$');

  @override
  CatalogObject? resolve(String normalized, List<CatalogObject> all) {
    final match = _pattern.firstMatch(normalized);
    if (match == null) return null;
    final number = int.tryParse(match.group(1)!);
    if (number == null) return null;
    return _findByNumber(all, CatalogType.messier, number);
  }
}

class _NgcResolver implements _CatalogTargetResolver {
  static final _pattern = RegExp(r'^NGC(\d+)$');

  @override
  CatalogObject? resolve(String normalized, List<CatalogObject> all) {
    final match = _pattern.firstMatch(normalized);
    if (match == null) return null;
    final number = int.tryParse(match.group(1)!);
    if (number == null) return null;
    return _findByNumber(all, CatalogType.ngc, number);
  }
}

class _IcResolver implements _CatalogTargetResolver {
  static final _pattern = RegExp(r'^IC(\d+)([AB])?$');

  @override
  CatalogObject? resolve(String normalized, List<CatalogObject> all) {
    final match = _pattern.firstMatch(normalized);
    if (match == null) return null;
    final number = int.tryParse(match.group(1)!);
    if (number == null) return null;
    final suffix = match.group(2);
    return _findByNumber(all, CatalogType.ic, number, suffix: suffix);
  }
}

class _CaldwellResolver implements _CatalogTargetResolver {
  static final _shortPattern = RegExp(r'^C(\d+)$');
  static final _longPattern = RegExp(r'^CALDWELL(\d+)$');

  @override
  CatalogObject? resolve(String normalized, List<CatalogObject> all) {
    final short = _shortPattern.firstMatch(normalized);
    final long = _longPattern.firstMatch(normalized);
    final numberStr = short?.group(1) ?? long?.group(1);
    if (numberStr == null) return null;
    final number = int.tryParse(numberStr);
    if (number == null) return null;
    return _findByNumber(all, CatalogType.caldwell, number);
  }
}

class _Sh2Resolver implements _CatalogTargetResolver {
  static final _pattern = RegExp(r'^SH2(\d+)$');

  @override
  CatalogObject? resolve(String normalized, List<CatalogObject> all) {
    final match = _pattern.firstMatch(normalized);
    if (match == null) return null;
    final number = int.tryParse(match.group(1)!);
    if (number == null) return null;
    return _findByNumber(all, CatalogType.sh2, number);
  }
}

class _RcwResolver implements _CatalogTargetResolver {
  static final _pattern = RegExp(r'^RCW(\d+)$');

  @override
  CatalogObject? resolve(String normalized, List<CatalogObject> all) {
    final match = _pattern.firstMatch(normalized);
    if (match == null) return null;
    final number = int.tryParse(match.group(1)!);
    if (number == null) return null;
    return _findByNumber(all, CatalogType.rcw, number);
  }
}

class _VdbResolver implements _CatalogTargetResolver {
  static final _pattern = RegExp(r'^VDB(\d+)$');

  @override
  CatalogObject? resolve(String normalized, List<CatalogObject> all) {
    final match = _pattern.firstMatch(normalized);
    if (match == null) return null;
    final number = int.tryParse(match.group(1)!);
    if (number == null) return null;
    return _findByNumber(all, CatalogType.vdb, number);
  }
}

CatalogObject? _findByNumber(
  List<CatalogObject> all,
  CatalogType type,
  int number, {
  String? suffix,
}) {
  CatalogObject? fallback;

  for (final obj in all) {
    if (obj.catalog != type || obj.number != number) continue;
    if (suffix != null) {
      if (obj.suffix != suffix) continue;
    } else if (obj.suffix != null && obj.suffix!.isNotEmpty) {
      continue;
    }

    if (obj.isPrimaryCatalog) {
      return obj;
    }
    fallback ??= obj;
  }

  if (suffix != null) {
    for (final obj in all) {
      if (obj.catalog == type &&
          obj.number == number &&
          obj.suffix == suffix) {
        if (obj.isPrimaryCatalog) {
          return obj;
        }
        fallback ??= obj;
      }
    }
  }

  return fallback;
}

final _resolvers = <_CatalogTargetResolver>[
  _MessierResolver(),
  _NgcResolver(),
  _IcResolver(),
  _CaldwellResolver(),
  _Sh2Resolver(),
  _RcwResolver(),
  _VdbResolver(),
];
