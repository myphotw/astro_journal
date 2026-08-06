/// 촬영 장비 시야(FOV) 가로×세로(°) 입력 파싱.
abstract final class FovInputParser {
  static const separators = ['×', 'x', 'X', '*'];

  /// `0.72×1.28`, `2.24 x 3.99` 등 단일 문자열 파싱.
  static (double width, double height)? parsePair(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    for (final separator in separators) {
      if (!trimmed.contains(separator)) continue;
      final parts = trimmed.split(separator);
      if (parts.length != 2) continue;
      final width = double.tryParse(parts[0].trim());
      final height = double.tryParse(parts[1].trim());
      if (width == null || height == null || width <= 0 || height <= 0) {
        return null;
      }
      return (width, height);
    }

    final single = double.tryParse(trimmed);
    if (single == null || single <= 0) return null;
    return (single, single);
  }

  static String format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    final two = value.toStringAsFixed(2);
    return two.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  static String formatPair(double width, double height) =>
      '${format(width)}×${format(height)}°';
}
