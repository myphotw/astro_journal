import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/catalog_type.dart';
import 'season_planner_service.dart';

/// 계절별 촬영대상 카탈로그 필터 선택 상태 저장.
///
/// 빈 집합은 "전체 선택"을 의미한다 ([SeasonPlannerViewModel]과 동일).
class SeasonPlannerFilterService {
  static const keyCatalogFilters = 'season_planner_catalog_filters_v1';
  static const _keyCatalogFilters = keyCatalogFilters;

  Future<Set<CatalogType>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_keyCatalogFilters);
    if (saved == null) return {};

    final plannerValues =
        SeasonPlannerService.plannerCatalogTypes.map((c) => c.value).toSet();

    return saved
        .where(plannerValues.contains)
        .map(CatalogType.fromValue)
        .toSet();
  }

  Future<void> save(Set<CatalogType> catalogFilters) async {
    final prefs = await SharedPreferences.getInstance();
    if (catalogFilters.isEmpty) {
      await prefs.remove(_keyCatalogFilters);
      return;
    }

    final values = catalogFilters.map((c) => c.value).toList()..sort();
    await prefs.setStringList(_keyCatalogFilters, values);
  }
}
