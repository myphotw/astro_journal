/// 별칭(일반 명칭)과 교차 카탈로그 식별자를 구분한다.
class CatalogReferenceClassifier {
  CatalogReferenceClassifier._();

  static final _hangul = RegExp(r'[\uac00-\ud7a3]');

  static final _crossCatalogPatterns = <RegExp>[
    RegExp(r'^NGC\s*\d', caseSensitive: false),
    RegExp(r'^IC\s*\d', caseSensitive: false),
    RegExp(r'^M\s*\d+$', caseSensitive: false),
    RegExp(r'^C\s*\d+$', caseSensitive: false),
    RegExp(r'^Caldwell\s*\d', caseSensitive: false),
    RegExp(r'^Sh2[\s\-]?\d', caseSensitive: false),
    RegExp(r'^RCW\s*\d', caseSensitive: false),
    RegExp(r'^vdB\s*\d', caseSensitive: false),
    RegExp(r'^MWSC\s*\d', caseSensitive: false),
    RegExp(r'^LBN\s*\d', caseSensitive: false),
    RegExp(r'^IRAS\s+', caseSensitive: false),
    RegExp(r'^PGC\s*\d', caseSensitive: false),
    RegExp(r'^UGC\s*\d', caseSensitive: false),
    RegExp(r'^UGCA\s*\d', caseSensitive: false),
    RegExp(r'^2MASX\s+', caseSensitive: false),
    RegExp(r'^Cr\s*\d', caseSensitive: false),
    RegExp(r'^Mel\s*\d', caseSensitive: false),
    RegExp(r'^PN\s+G', caseSensitive: false),
    RegExp(r'^HD\s+\d', caseSensitive: false),
    RegExp(r'^HIP\s+\d', caseSensitive: false),
    RegExp(r'^BD\s+[+\-]', caseSensitive: false),
    RegExp(r'^ESO[\s\-]', caseSensitive: false),
    RegExp(r'^SaO\s+\d', caseSensitive: false),
    RegExp(r'^TYC\s+\d', caseSensitive: false),
    RegExp(r'^GSC\s+\d', caseSensitive: false),
    RegExp(r'^LDN\s+\d', caseSensitive: false),
    RegExp(r'^B\s+\d{3,}', caseSensitive: false),
    RegExp(r'^(NGC|IC|SH2|RCW|VDB|MWSC|LBN|PGC|UGC)\d+', caseSensitive: false),
    RegExp(r'^Caldwell\d+$', caseSensitive: false),
    RegExp(r'^Sh2\d+$', caseSensitive: false),
  ];

  static bool isCrossCatalogReference(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (_hangul.hasMatch(trimmed)) return false;
    return _crossCatalogPatterns.any((pattern) => pattern.hasMatch(trimmed));
  }

  static ({List<String> aliases, List<String> crossCatalogRefs}) split(
    Iterable<String> values,
  ) {
    final aliases = <String>[];
    final crossCatalogRefs = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      if (isCrossCatalogReference(trimmed)) {
        crossCatalogRefs.add(trimmed);
      } else {
        aliases.add(trimmed);
      }
    }
    return (aliases: aliases, crossCatalogRefs: crossCatalogRefs);
  }
}
