/// 카탈로그 메타데이터 표시용 숫자·단위 포맷.
abstract final class CatalogMetadataFormat {
  /// 광년 거리 표시. 없거나 0 이하면 null.
  /// 예: 7200 → "7,200 광년", 8.6 → "8.6 광년"
  static String? formatDistanceLy(num? distanceLy) {
    if (distanceLy == null || distanceLy <= 0) return null;
    final value = distanceLy.toDouble();
    if (value == value.roundToDouble()) {
      return '${_withThousands(value.round())} 광년';
    }
    final rounded = (value * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return '${_withThousands(rounded.round())} 광년';
    }
    final whole = rounded.truncate();
    final fraction = ((rounded - whole) * 10).round();
    return '${_withThousands(whole)}.$fraction 광년';
  }

  /// 각크기 표시용. 불필요한 `.00`을 제거하고 ′ 단위를 통일한다.
  /// 예: `36.00'` → `36′`, `35.50' × 60.00'` → `35.5′ × 60′`
  static String formatAngularSize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '-') return trimmed;

    return trimmed.replaceAllMapped(
      RegExp(r"(\d+(?:\.\d+)?)\s*['′]"),
      (match) {
        final number = double.tryParse(match.group(1)!);
        if (number == null) return match.group(0)!;
        return '${_formatArcminNumber(number)}′';
      },
    );
  }

  static String _formatArcminNumber(double value) {
    final rounded = (value * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return '${rounded.round()}';
    }
    return rounded.toStringAsFixed(1);
  }

  static String _withThousands(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final reverseIndex = digits.length - i;
      buffer.write(digits[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(',');
      }
    }
    return negative ? '-$buffer' : buffer.toString();
  }
}
