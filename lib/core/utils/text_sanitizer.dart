/// CJK(한자) 제거 및 텍스트 정리.
abstract final class TextSanitizer {
  static final _hanziPattern = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]');

  static bool containsHanzi(String? value) =>
      value != null && _hanziPattern.hasMatch(value);

  static String stripHanzi(String? value) {
    if (value == null || value.isEmpty) {
      return '';
    }
    var cleaned = value.replaceAll(_hanziPattern, '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r'^[|,\s]+|[|,\s]+$'), '');
    return cleaned;
  }

  static String? sanitizeOptional(String? value) {
    if (value == null) {
      return null;
    }
    final cleaned = stripHanzi(value);
    if (cleaned.isEmpty || cleaned == '-') {
      return null;
    }
    return cleaned;
  }

  /// 한자 제거 + 가로 공백만 정리. 줄바꿈(\n)은 유지한다.
  static String? sanitizeMultilineOptional(String? value) {
    if (value == null) {
      return null;
    }
    final withoutHanzi = value.replaceAll(_hanziPattern, '');
    final normalized = withoutHanzi
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trimRight())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (normalized.isEmpty || normalized == '-') {
      return null;
    }
    return normalized;
  }

  static String sanitizeRequired(String? value, {String fallback = '-'}) {
    final cleaned = sanitizeOptional(value);
    return cleaned ?? fallback;
  }

  static List<String> sanitizeList(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final cleaned = sanitizeOptional(value);
      if (cleaned == null || seen.contains(cleaned)) {
        continue;
      }
      seen.add(cleaned);
      result.add(cleaned);
    }
    return result;
  }

  static String? sanitizeSearchKeywords(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final parts = value
        .split('|')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && !containsHanzi(part))
        .toList();
    if (parts.isEmpty) {
      return null;
    }
    return parts.join('|');
  }
}
