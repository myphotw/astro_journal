import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/utils/text_sanitizer.dart';
import '../data/models/catalog_object.dart';
import 'catalog_search_service.dart';

/// Alias·Dictionary 기반 Display Name 결정.
abstract final class CatalogDisplayNameResolver {
  static const _assetPath = 'assets/catalog/display_name_dictionary.json';
  static const _hangulPattern = r'[\uAC00-\uD7A3]';
  static final _catalogRefPattern = RegExp(
    r'^(M\d{1,3}|NGC\s*\d+|IC\s*\d+[AB]?|C\d{1,3}|Sh2[-\s]?\d+|RCW\s*\d+|vdB\s*\d+|Barnard\s*\d+|LDN\s*\d+|LBN\s*\d+)$',
    caseSensitive: false,
  );

  static Map<String, String> _dictionary = {};
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final jsonString = await rootBundle.loadString(_assetPath);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final entries = data['entries'] as Map<String, dynamic>? ?? {};
      _dictionary = entries.map(
        (key, value) => MapEntry(_normalizeKey(key), value as String),
      );
    } catch (_) {
      _dictionary = {};
    }
    _loaded = true;
  }

  /// 카드·리스트용 Display Name (우선순위 체인).
  static String? resolve(CatalogObject object) {
    final aliases = _collectAliases(object);

    for (final alias in aliases) {
      if (_containsHangul(alias)) {
        final cleaned = TextSanitizer.sanitizeOptional(alias);
        if (cleaned != null && !_isCatalogReference(cleaned)) {
          return cleaned;
        }
      }
    }

    for (final alias in aliases) {
      if (_containsHangul(alias)) continue;
      final translated = _translateEnglish(alias);
      if (translated != null) {
        return translated;
      }
    }

    final commonName = TextSanitizer.sanitizeOptional(object.commonName);
    if (commonName != null && !_labelsMatch(commonName, object.displayName)) {
      return commonName;
    }

    final name = TextSanitizer.sanitizeOptional(object.name);
    if (name != null && !_labelsMatch(name, object.displayName)) {
      return name;
    }

    final type = TextSanitizer.sanitizeOptional(object.displayType);
    // "기타"는 Display Name이 아니라 유형 라벨이므로 이름으로 쓰지 않는다.
    if (type != null && type != '기타') {
      return type;
    }
    return null;
  }

  /// 카드 부제용: Catalog Name과 같으면 null.
  static String? uiDisplayName(CatalogObject object) {
    final candidate = resolve(object);
    if (candidate == null) {
      return null;
    }
    if (_labelsMatch(candidate, object.displayName)) {
      return null;
    }
    return candidate;
  }

  static int get dictionaryEntryCount => _dictionary.length;

  static List<String> _collectAliases(CatalogObject object) {
    final seen = <String>{};
    final aliases = <String>[];

    void add(String? value) {
      final cleaned = TextSanitizer.sanitizeOptional(value);
      if (cleaned == null) return;
      final key = _normalizeKey(cleaned);
      if (seen.add(key)) {
        aliases.add(cleaned);
      }
    }

    for (final alias in object.displayAliases) {
      add(alias);
    }

    final global = CatalogSearchService.globalAliases[object.id] ?? const [];
    for (final alias in global) {
      add(alias);
    }

    return aliases;
  }

  static String? _translateEnglish(String alias) {
    final direct = _dictionary[_normalizeKey(alias)];
    if (direct != null) {
      return direct;
    }

    final withoutApostrophe = alias.replaceAll("'", '').replaceAll('’', '');
    return _dictionary[_normalizeKey(withoutApostrophe)];
  }

  static bool _containsHangul(String value) =>
      RegExp(_hangulPattern).hasMatch(value);

  static bool _isCatalogReference(String value) =>
      _catalogRefPattern.hasMatch(value.replaceAll(' ', ''));

  static String _normalizeKey(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('’', "'");
  }

  static bool _labelsMatch(String a, String b) {
    final normalizedA = a.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final normalizedB = b.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return normalizedA == normalizedB;
  }
}
