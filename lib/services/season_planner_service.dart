import 'dart:math' as math;

import '../core/constants/astro_season.dart';
import '../core/constants/catalog_type.dart';
import '../data/models/catalog_object.dart';
import '../data/models/season_planner_item.dart';
import 'celestial_position_service.dart';

/// RA·월 기준 계절/월별 촬영 적합도 계산.
class SeasonPlannerService {
  const SeasonPlannerService();

  static const optimalRaByMonth = [7, 9, 11, 13, 15, 17, 19, 21, 23, 1, 3, 5];

  static const monthLabels = [
    '1월',
    '2월',
    '3월',
    '4월',
    '5월',
    '6월',
    '7월',
    '8월',
    '9월',
    '10월',
    '11월',
    '12월',
  ];

  /// 계절 플래너에서 제외할 카탈로그 (RA 기반 추천과 맞지 않음).
  static bool isSeasonPlannerEligible(CatalogObject object) {
    return object.catalog != CatalogType.solar &&
        object.catalog != CatalogType.milky;
  }

  /// RA 문자열이 계절 계산에 사용 가능한지 확인한다.
  static bool hasValidRa(String ra) {
    final trimmed = ra.trim();
    if (trimmed.isEmpty || trimmed == '-') return false;
    return RegExp(r'\d+h', caseSensitive: false).hasMatch(trimmed);
  }

  /// DB 저장용 계절 정보 (없으면 null).
  SeasonFields? computeSeasonFields(CatalogObject object) {
    if (!isSeasonPlannerEligible(object) || !hasValidRa(object.ra)) {
      return null;
    }

    final peak = peakMonth(object);
    final season = AstroSeason.fromMonth(peak);
    return SeasonFields(
      peakMonth: peak,
      label:
          '최적 ${monthLabels[peak - 1]} · ${season.label} (${season.subtitle})',
    );
  }

  String formatSeasonLabel(CatalogObject object) {
    final fields = computeSeasonFields(object);
    return fields?.label ?? '-';
  }

  double scoreForMonth(CatalogObject object, int month) {
    if (!isSeasonPlannerEligible(object) || !hasValidRa(object.ra)) return 0;
    final raHours = CelestialPositionService.parseRaHours(object.ra);
    if (raHours.isNaN) return 0;

    final optimalRa = optimalRaByMonth[month - 1].toDouble();
    final dist = _raDistance(optimalRa, raHours);
    return (math.max(0.0, 1 - dist / 12.0) * 100.0).clamp(0.0, 100.0);
  }

  /// 계절 내 월 중 최고 점수.
  double scoreForSeason(CatalogObject object, AstroSeason season) {
    var best = 0.0;
    for (final month in season.months) {
      final score = scoreForMonth(object, month);
      if (score > best) best = score;
    }
    return best;
  }

  int peakMonth(CatalogObject object) {
    var bestMonth = 1;
    var bestScore = -1.0;
    for (var month = 1; month <= 12; month++) {
      final score = scoreForMonth(object, month);
      if (score > bestScore) {
        bestScore = score;
        bestMonth = month;
      }
    }
    return bestMonth;
  }

  String peakMonthLabel(CatalogObject object) => monthLabels[peakMonth(object) - 1];

  String seasonRangeLabel(CatalogObject object) {
    final peak = peakMonth(object);
    final season = AstroSeason.fromMonth(peak);
    return '${season.label} (${season.subtitle})';
  }

  static const plannerCatalogTypes = [
    CatalogType.messier,
    CatalogType.ngc,
    CatalogType.ic,
    CatalogType.caldwell,
    CatalogType.sh2,
    CatalogType.rcw,
    CatalogType.vdb,
  ];

  List<SeasonPlannerItem> buildItems({
    required List<CatalogObject> objects,
    required int month,
    AstroSeason? season,
    bool uncapturedOnly = false,
    Set<CatalogType>? catalogFilters,
    double minScore = 25,
    Map<String, String>? thumbnails,
  }) {
    final filtered = objects.where(isSeasonPlannerEligible);
    final catalogFiltered = catalogFilters == null || catalogFilters.isEmpty
        ? filtered
        : filtered.where((o) => catalogFilters.contains(o.catalog));
    final captureFiltered = uncapturedOnly
        ? catalogFiltered.where((o) => !o.captured)
        : catalogFiltered;

    final items = <SeasonPlannerItem>[];
    for (final object in captureFiltered) {
      final peak = peakMonth(object);
      if (season != null) {
        if (!season.months.contains(peak)) continue;
      } else if (peak != month) {
        continue;
      }

      final score = season != null
          ? scoreForSeason(object, season)
          : scoreForMonth(object, month);
      if (score < minScore) continue;

      items.add(
        SeasonPlannerItem(
          object: object,
          score: score,
          peakMonth: peak,
          thumbnailPath: thumbnails?[object.id],
        ),
      );
    }

    items.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.object.displayId.compareTo(b.object.displayId);
    });

    return items;
  }

  SeasonSummary summarize({
    required List<CatalogObject> objects,
    required int month,
    AstroSeason? season,
    double minScore = 25,
  }) {
    final all = buildItems(
      objects: objects,
      month: month,
      season: season,
      minScore: minScore,
    );
    final uncaptured = buildItems(
      objects: objects,
      month: month,
      season: season,
      uncapturedOnly: true,
      minScore: minScore,
    );
    return SeasonSummary(total: all.length, uncaptured: uncaptured.length);
  }

  double _raDistance(double ra1, double ra2) {
    var diff = (ra1 - ra2).abs();
    if (diff > 12) diff = 24 - diff;
    return diff;
  }
}

class SeasonSummary {
  const SeasonSummary({required this.total, required this.uncaptured});

  final int total;
  final int uncaptured;
}

class SeasonFields {
  const SeasonFields({required this.peakMonth, required this.label});

  final int peakMonth;
  final String label;
}
