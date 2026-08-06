/// 교차 카탈로그 참조 문자열을 DB object ID로 해석한다.
abstract final class CatalogReferenceResolver {
  static String normalizeKey(String value) =>
      value.replaceAll(RegExp(r'[\s\-_]+'), '').toUpperCase();

  static Map<String, String> buildLookup(Iterable<String> ids) {
    final lookup = <String, String>{};
    for (final id in ids) {
      lookup[normalizeKey(id)] = id;
    }
    return lookup;
  }

  static String? resolve(String ref, Map<String, String> lookup) {
    final key = normalizeKey(ref);
    final direct = lookup[key];
    if (direct != null) {
      return direct;
    }

    final messier = RegExp(r'^M(\d+)$').firstMatch(key);
    if (messier != null) {
      return lookup['M${messier.group(1)}'];
    }

    final ngc = RegExp(r'^NGC(\d+)([AB])?$').firstMatch(key);
    if (ngc != null) {
      final suffix = ngc.group(2) ?? '';
      return lookup['NGC${ngc.group(1)}$suffix'];
    }

    final ic = RegExp(r'^IC(\d+)([AB])?$').firstMatch(key);
    if (ic != null) {
      final suffix = ic.group(2) ?? '';
      return lookup['IC${ic.group(1)}$suffix'];
    }

    final sh2 = RegExp(r'^SH2(\d+)$').firstMatch(key);
    if (sh2 != null) {
      return lookup['SH2-${sh2.group(1)}'] ?? lookup['SH2${sh2.group(1)}'];
    }

    final rcw = RegExp(r'^RCW(\d+)$').firstMatch(key);
    if (rcw != null) {
      return lookup['RCW${rcw.group(1)}'];
    }

    final caldwell = RegExp(r'^C(\d+)$').firstMatch(key);
    if (caldwell != null) {
      return lookup['C${caldwell.group(1)}'];
    }

    final barnard = RegExp(r'^B(\d+)$').firstMatch(key);
    if (barnard != null) {
      return lookup['B${barnard.group(1)}'];
    }

    final ldn = RegExp(r'^LDN(\d+)$').firstMatch(key);
    if (ldn != null) {
      return lookup['LDN${ldn.group(1)}'];
    }

    final lbn = RegExp(r'^LBN(\d+)$').firstMatch(key);
    if (lbn != null) {
      return lookup['LBN${lbn.group(1)}'];
    }

    final vdb = RegExp(r'^VDB(\d+)$').firstMatch(key);
    if (vdb != null) {
      return lookup['VDB${vdb.group(1)}'] ?? lookup['vdB${vdb.group(1)}'];
    }

    return null;
  }
}
