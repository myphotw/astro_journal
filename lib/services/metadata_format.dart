/// 메타데이터 표시용 시간/노출 포맷 유틸.
class MetadataFormat {
  MetadataFormat._();

  /// 분 입력값 → 실시간 표시용 "1시간 30분" (공백 포함).
  ///
  /// 비어 있거나 숫자가 아니면 null.
  static String? formatMinutesLive(String rawMinutes) {
    final trimmed = rawMinutes.trim();
    if (trimmed.isEmpty) return null;
    final minutes = double.tryParse(trimmed);
    if (minutes == null || minutes < 0) return null;
    return formatMinutesLabel(minutes);
  }

  /// 분 → "30분", "1시간 30분", "2시간".
  static String formatMinutesLabel(double minutes) {
    if (minutes <= 0) return '0분';
    final totalMinutes = minutes.round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h > 0 && m > 0) return '$h시간 $m분';
    if (h > 0) return '$h시간';
    return '$m분';
  }

  /// 분 입력 → DB 저장용 한국어 노출 문자열 (`formatSeconds`와 동일 규칙).
  static String? formatMinutesInputToExposure(String rawMinutes) {
    final trimmed = rawMinutes.trim();
    if (trimmed.isEmpty) return null;
    final minutes = double.tryParse(trimmed);
    if (minutes == null || minutes < 0) return null;
    return formatSeconds(minutes * 60);
  }

  /// "4분20초" / "90" / "2h 30m" → 분 입력란용 숫자 문자열.
  ///
  /// 단위 없는 숫자는 이미 분 값으로 간주한다.
  static String minutesNumberFromDisplay(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final asMinutes = double.tryParse(trimmed);
    if (asMinutes != null) {
      return _formatMinuteNumber(asMinutes);
    }

    final seconds = secondsFromDisplay(trimmed);
    if (seconds == null) return '';
    return _formatMinuteNumber(seconds / 60);
  }

  static String _formatMinuteNumber(double minutes) {
    if ((minutes - minutes.round()).abs() < 0.05) {
      return '${minutes.round()}';
    }
    final fixed = minutes.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  /// 표시 문자열 → 초. 파싱 실패 시 null.
  static double? secondsFromDisplay(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final asNum = double.tryParse(trimmed);
    if (asNum != null) return asNum;

    var total = 0.0;
    var matched = false;
    final hour = RegExp(r'(\d+(?:\.\d+)?)\s*시간').firstMatch(trimmed);
    final minKo = RegExp(r'(\d+(?:\.\d+)?)\s*분').firstMatch(trimmed);
    final secKo = RegExp(r'(\d+(?:\.\d+)?)\s*초').firstMatch(trimmed);
    final hourEn = RegExp(r'(\d+(?:\.\d+)?)\s*h\b', caseSensitive: false)
        .firstMatch(trimmed);
    final minEn = RegExp(r'(\d+(?:\.\d+)?)\s*m(?:in)?\b', caseSensitive: false)
        .firstMatch(trimmed);
    final secEn = RegExp(r'(\d+(?:\.\d+)?)\s*s(?:ec)?\b', caseSensitive: false)
        .firstMatch(trimmed);

    if (hour != null) {
      total += double.parse(hour.group(1)!) * 3600;
      matched = true;
    }
    if (hourEn != null) {
      total += double.parse(hourEn.group(1)!) * 3600;
      matched = true;
    }
    if (minKo != null) {
      total += double.parse(minKo.group(1)!) * 60;
      matched = true;
    }
    if (minEn != null) {
      total += double.parse(minEn.group(1)!) * 60;
      matched = true;
    }
    if (secKo != null) {
      total += double.parse(secKo.group(1)!);
      matched = true;
    }
    if (secEn != null) {
      total += double.parse(secEn.group(1)!);
      matched = true;
    }
    if (matched && total > 0) return total;

    final digits = RegExp(r'[\d.]+').firstMatch(trimmed.replaceAll(',', ''));
    if (digits == null) return null;
    return double.tryParse(digits.group(0)!);
  }

  /// 초 → "20초", "4분20초" 형식.
  static String formatSeconds(double sec) {
    if (sec >= 3600) {
      final h = (sec / 3600).floor();
      final m = ((sec % 3600) / 60).floor();
      final s = (sec % 60).round();
      if (s == 0 && m > 0) return '$h시간$m분';
      if (s == 0) return '$h시간';
      return '$h시간$m분$s초';
    }
    if (sec >= 60) {
      final m = (sec / 60).floor();
      final s = (sec % 60).round();
      if (s == 0) return '$m분';
      return '$m분$s초';
    }
    if (sec == sec.roundToDouble()) {
      return '${sec.toStringAsFixed(0)}초';
    }
    return '${sec.toStringAsFixed(1)}초';
  }

  /// ISO 8601 → "2026-06-13 00:40" 표시.
  static String formatDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso.replaceFirst(' ', 'T'));
    if (dt == null) return iso;
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }

  /// ISO 8601 → 입력란용 "2026-06-13 00:40:10".
  static String formatDateTimeInput(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso.replaceFirst(' ', 'T'));
    if (dt == null) return iso;
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}:${p(dt.second)}';
  }

  /// 스택 수 표시 (예: "13장").
  static String formatStackCount(int count) => '$count장';
}
