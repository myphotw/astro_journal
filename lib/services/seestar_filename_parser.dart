import '../data/models/seestar_metadata.dart';
import 'app_logger.dart';

/// Seestar 파일명을 파싱하여 메타데이터를 추출한다.
///
/// 지원 파일명 형식:
///   `Stacked_N_OBJ_Xs_FILTER_YYYYMMDD-HHMMSS.ext`
///
/// 예시:
///   `Stacked_13_M 27_20.0s_LP_20260613-004010.jpg`
///   → 스택수=13, 대상=M27, 노출=20.0s, 필터=LP, 날짜=2026-06-13 00:40:10
///
/// 총 적분시간은 스택수 × 1장 노출시간으로 계산한다.
class SeestarFilenameParser {
  const SeestarFilenameParser();

  static final _pattern = RegExp(
    r'^Stacked_(\d+)_(.+?)_([\d.]+)s_([^_]+)_(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})\.\w+$',
    caseSensitive: false,
  );

  /// [filename] 을 파싱하여 [SeestarMetadata]를 반환한다.
  ///
  /// 패턴에 맞지 않으면 null을 반환한다.
  SeestarMetadata? parse(String? filename) {
    if (filename == null || filename.trim().isEmpty) return null;

    final match = _pattern.firstMatch(filename.trim());
    if (match == null) {
      AppLogger.metadata('SeestarFilenameParser', '패턴 불일치: $filename');
      return null;
    }

    try {
      final stackNum = int.tryParse(match.group(1) ?? '');
      final objName = match.group(2)?.trim();
      final expSec = double.tryParse(match.group(3) ?? '');
      final filter = match.group(4)?.trim();

      final year = int.tryParse(match.group(5) ?? '');
      final month = int.tryParse(match.group(6) ?? '');
      final day = int.tryParse(match.group(7) ?? '');
      final hour = int.tryParse(match.group(8) ?? '');
      final minute = int.tryParse(match.group(9) ?? '');
      final second = int.tryParse(match.group(10) ?? '');

      String? dateStr;
      if (year != null &&
          month != null &&
          day != null &&
          hour != null &&
          minute != null &&
          second != null) {
        final dt = DateTime(year, month, day, hour, minute, second);
        dateStr = dt.toIso8601String();
      }

      double? totExpSec;
      if (stackNum != null && expSec != null) {
        totExpSec = stackNum * expSec;
      }

      final metadata = SeestarMetadata(
        objName: objName?.isEmpty == true ? null : objName,
        date: dateStr,
        stackNum: stackNum,
        expSec: expSec,
        totExpSec: totExpSec,
        filter: filter?.isEmpty == true ? null : filter,
      );

      AppLogger.metadata(
        'SeestarFilenameParser',
        '파싱 완료 — 대상=${metadata.objName ?? "없음"}, '
            '스택=${metadata.stackNum ?? "없음"}, '
            '노출=${metadata.expSec ?? "없음"}s, '
            '필터=${metadata.filter ?? "없음"}, '
            '날짜=${metadata.date ?? "없음"}',
      );

      return metadata;
    } catch (e) {
      AppLogger.metadata('SeestarFilenameParser', '파싱 실패: $e');
      return null;
    }
  }
}
