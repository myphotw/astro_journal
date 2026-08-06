import '../core/constants/constellation_names.dart';
import '../data/models/catalog_object.dart';

/// 카탈로그 로드 시 1회 구축하는 검색 인덱스 (인메모리 고속 검색).
class CatalogSearchIndex {
  CatalogSearchIndex._(this._entries, this._designationLookup);

  factory CatalogSearchIndex.build(
    List<CatalogObject> objects, {
    Map<String, List<String>> globalAliases = const {},
    Map<String, List<String>> globalCrossCatalog = const {},
  }) {
    final entries = <_IndexedCatalogObject>[];
    final designationLookup = <String, CatalogObject>{};

    for (final object in objects) {
      final entry = _IndexedCatalogObject(
        object: object,
        globalAliases: globalAliases,
        globalCrossCatalog: globalCrossCatalog,
      );
      entries.add(entry);
      designationLookup[entry.normalizedDisplayName] = object;
      designationLookup[entry.normalizedId] = object;
    }

    return CatalogSearchIndex._(entries, designationLookup);
  }

  /// UI 스레드를 막지 않도록 청크 단위로 인덱스를 만든다.
  static Future<CatalogSearchIndex> buildAsync(
    List<CatalogObject> objects, {
    Map<String, List<String>> globalAliases = const {},
    Map<String, List<String>> globalCrossCatalog = const {},
    int chunkSize = 200,
  }) async {
    final entries = <_IndexedCatalogObject>[];
    final designationLookup = <String, CatalogObject>{};

    for (var i = 0; i < objects.length; i++) {
      final object = objects[i];
      final entry = _IndexedCatalogObject(
        object: object,
        globalAliases: globalAliases,
        globalCrossCatalog: globalCrossCatalog,
      );
      entries.add(entry);
      designationLookup[entry.normalizedDisplayName] = object;
      designationLookup[entry.normalizedId] = object;

      if (i % chunkSize == chunkSize - 1) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    return CatalogSearchIndex._(entries, designationLookup);
  }

  final List<_IndexedCatalogObject> _entries;
  final Map<String, CatalogObject> _designationLookup;

  int get length => _entries.length;

  List<CatalogObject> search(String query, {int limit = 50}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) {
      return const [];
    }

    final lowerQuery = trimmed.toLowerCase();
    final normalizedQuery = _normalize(trimmed);

    if (_isCatalogDesignationQuery(normalizedQuery)) {
      final exact = _designationLookup[normalizedQuery];
      if (exact != null) {
        return [exact];
      }
    }

    final top = _TopKScored(limit);
    for (final entry in _entries) {
      final score = entry.score(lowerQuery, normalizedQuery);
      if (score > 0) {
        top.add(entry.object, score);
      }
    }
    return top.toObjects();
  }

  static String _normalize(String input) =>
      input.replaceAll(RegExp(r'[\s\-_]+'), '').toUpperCase();

  static bool _isCatalogDesignationQuery(String normalizedQuery) {
    return RegExp(r'^(M\d+|NGC\d+|IC\d+[AB]?|C\d+|SH2\d+|RCW\d+|VDB\d+)$')
        .hasMatch(normalizedQuery);
  }
}

class _IndexedCatalogObject {
  _IndexedCatalogObject({
    required this.object,
    required Map<String, List<String>> globalAliases,
    required Map<String, List<String>> globalCrossCatalog,
  })  : normalizedDisplayName = _normalize(object.displayName),
        normalizedId = _normalize(object.id),
        _globalAliases = globalAliases[object.id] ?? const [],
        _globalCrossCatalog = globalCrossCatalog[object.id] ?? const [],
        lowerBlob = _buildLowerBlob(
          object,
          globalAliases,
          globalCrossCatalog,
        ),
        normalizedBlob = _buildNormalizedBlob(
          object,
          globalAliases,
          globalCrossCatalog,
        );

  final CatalogObject object;
  final List<String> _globalAliases;
  final List<String> _globalCrossCatalog;
  final String normalizedDisplayName;
  final String normalizedId;
  final String lowerBlob;
  final String normalizedBlob;

  int score(String lowerQuery, String normalizedQuery) {
    if (!lowerBlob.contains(lowerQuery) &&
        !normalizedBlob.contains(normalizedQuery)) {
      return 0;
    }

    var best = 0;

    void consider(String? text) {
      if (text == null || text.isEmpty) {
        return;
      }
      final lower = text.toLowerCase();
      final normalized = _normalize(text);
      final value = _textScore(lower, normalized, lowerQuery, normalizedQuery);
      if (value > best) {
        best = value;
      }
    }

    consider(object.displayName);
    consider(object.displayCommonName);
    consider(object.name);
    consider(object.commonName);
    consider(object.objectType);
    consider(object.type);
    consider(object.constellation);
    consider(object.displayConstellation);
    if (object.searchKeywords != null && object.searchKeywords!.isNotEmpty) {
      for (final term in object.searchKeywords!.split('|')) {
        consider(term.trim());
      }
    }
    for (final term in ConstellationNames.searchTerms(object.constellation)) {
      consider(term);
    }
    for (final alias in object.aliases) {
      consider(alias);
    }
    for (final ref in object.crossCatalogRefs) {
      consider(ref);
    }
    for (final tag in object.tags) {
      consider(tag);
    }
    for (final alias in _globalAliases) {
      consider(alias);
    }
    for (final ref in _globalCrossCatalog) {
      consider(ref);
    }

    return best;
  }

  static String _buildLowerBlob(
    CatalogObject object,
    Map<String, List<String>> globalAliases,
    Map<String, List<String>> globalCrossCatalog,
  ) {
    final parts = <String>[
      object.displayName,
      object.displayCommonName,
      object.name,
      if (object.commonName != null) object.commonName!,
      object.type,
      if (object.objectType != null) object.objectType!,
      object.constellation,
      object.displayConstellation,
      if (object.searchKeywords != null) object.searchKeywords!,
      ...object.aliases,
      ...object.crossCatalogRefs,
      ...object.tags,
      ...?globalAliases[object.id],
      ...?globalCrossCatalog[object.id],
      ...ConstellationNames.searchTerms(object.constellation),
    ];
    return parts.join('\n').toLowerCase();
  }

  static String _buildNormalizedBlob(
    CatalogObject object,
    Map<String, List<String>> globalAliases,
    Map<String, List<String>> globalCrossCatalog,
  ) {
    final parts = <String>[
      object.displayName,
      object.displayCommonName,
      object.name,
      if (object.commonName != null) object.commonName!,
      if (object.searchKeywords != null) object.searchKeywords!,
      ...object.aliases,
      ...object.crossCatalogRefs,
      ...?globalAliases[object.id],
      ...?globalCrossCatalog[object.id],
    ];
    return parts.map(_normalize).join('\n');
  }

  static String _normalize(String input) =>
      input.replaceAll(RegExp(r'[\s\-_]+'), '').toUpperCase();

  static int _textScore(
    String lowerText,
    String normalizedText,
    String lowerQuery,
    String normalizedQuery,
  ) {
    if (CatalogSearchIndex._isCatalogDesignationQuery(normalizedQuery)) {
      if (normalizedText == normalizedQuery) {
        return 100;
      }
      if (normalizedText.startsWith(normalizedQuery)) {
        final rest = normalizedText.substring(normalizedQuery.length);
        if (rest.isEmpty || RegExp(r'^[A-Z]').hasMatch(rest)) {
          return 0;
        }
      }
      return 0;
    }

    if (normalizedText == normalizedQuery) return 100;
    if (lowerText == lowerQuery) return 95;
    if (normalizedText.startsWith(normalizedQuery)) return 80;
    if (lowerText.startsWith(lowerQuery)) return 75;
    if (normalizedText.contains(normalizedQuery)) return 60;
    if (lowerText.contains(lowerQuery)) return 55;
    return 0;
  }
}

class _TopKScored {
  _TopKScored(this._limit);

  final int _limit;
  final List<_ScoredCatalogObject> _items = [];

  /// 텍스트 점수(내림차순) → 대표 천체 우선 → displayPriority(오름차순) → 이름순.
  /// 동일 검색 점수에서는 대표 천체를 먼저 노출한다.
  static int _compare(_ScoredCatalogObject a, _ScoredCatalogObject b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    if (a.object.isFeatured != b.object.isFeatured) {
      return a.object.isFeatured ? -1 : 1;
    }
    final byPriority =
        a.object.displayPriority.compareTo(b.object.displayPriority);
    if (byPriority != 0) return byPriority;
    return a.object.displayName.compareTo(b.object.displayName);
  }

  void add(CatalogObject object, int score) {
    final item = _ScoredCatalogObject(object, score);
    if (_items.length < _limit) {
      _items.add(item);
      if (_items.length == _limit) {
        _items.sort(_compare);
      }
      return;
    }

    if (_compare(item, _items.last) >= 0) {
      return;
    }

    var insertAt = _items.length;
    for (var i = 0; i < _items.length; i++) {
      if (_compare(item, _items[i]) < 0) {
        insertAt = i;
        break;
      }
    }
    _items.insert(insertAt, item);
    _items.removeLast();
  }

  List<CatalogObject> toObjects() {
    if (_items.length > 1 && _items.length < _limit) {
      _items.sort(_compare);
    }
    return _items.map((item) => item.object).toList(growable: false);
  }
}

class _ScoredCatalogObject {
  const _ScoredCatalogObject(this.object, this.score);
  final CatalogObject object;
  final int score;
}
