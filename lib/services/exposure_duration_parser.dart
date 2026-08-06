/// 촬영 기록의 적분시간 문자열을 초 단위로 변환한다.
class ExposureDurationParser {
  const ExposureDurationParser();

  /// 파싱 실패·빈 문자열은 0초.
  double parse(String? raw) {
    if (raw == null) return 0;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 0;

    final korean = _parseKoreanDuration(trimmed);
    if (korean != null) return korean;

    final minutes = _parseMinutesSuffix(trimmed);
    if (minutes != null) return minutes;

    final numeric = double.tryParse(trimmed.replaceAll(',', ''));
    if (numeric != null && numeric >= 0) return numeric;

    return 0;
  }

  double? _parseKoreanDuration(String value) {
    final hourMatch = RegExp(r'(\d+(?:\.\d+)?)\s*시간').firstMatch(value);
    final minuteMatch = RegExp(r'(\d+(?:\.\d+)?)\s*분').firstMatch(value);
    final secondMatch = RegExp(r'(\d+(?:\.\d+)?)\s*초').firstMatch(value);

    if (hourMatch == null &&
        minuteMatch == null &&
        secondMatch == null &&
        !value.contains('시간') &&
        !value.contains('분') &&
        !value.contains('초')) {
      return null;
    }

    var total = 0.0;
    if (hourMatch != null) {
      total += double.parse(hourMatch.group(1)!) * 3600;
    }
    if (minuteMatch != null) {
      total += double.parse(minuteMatch.group(1)!) * 60;
    }
    if (secondMatch != null) {
      total += double.parse(secondMatch.group(1)!);
    }
    return total;
  }

  double? _parseMinutesSuffix(String value) {
    final match = RegExp(
      r'^(\d+(?:\.\d+)?)\s*min(?:ute)?s?$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    return double.parse(match.group(1)!) * 60;
  }
}
