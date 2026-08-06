import 'catalog_object.dart';

/// 계절/월별 촬영 대상 목록 항목.
class SeasonPlannerItem {
  const SeasonPlannerItem({
    required this.object,
    required this.score,
    required this.peakMonth,
    this.thumbnailPath,
  });

  final CatalogObject object;

  /// 0~100, 선택한 계절/월에 대한 적합도.
  final double score;

  /// RA 기준 1년 중 가장 잘 보이는 달 (1~12).
  final int peakMonth;

  final String? thumbnailPath;
}
