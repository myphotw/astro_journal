import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/services/season_planner_filter_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SeasonPlannerFilterService', () {
    late SeasonPlannerFilterService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = SeasonPlannerFilterService();
    });

    test('load returns empty set when nothing saved (all catalogs)', () async {
      expect(await service.load(), isEmpty);
    });

    test('save and load restores partial catalog selection', () async {
      await service.save({CatalogType.ngc, CatalogType.ic});
      final loaded = await service.load();

      expect(loaded, {CatalogType.ngc, CatalogType.ic});
    });

    test('save empty set clears persisted filters', () async {
      await service.save({CatalogType.messier});
      await service.save({});

      expect(await service.load(), isEmpty);
    });

    test('load ignores unknown catalog values', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        SeasonPlannerFilterService.keyCatalogFilters,
        ['ngc', 'unknown_catalog'],
      );

      expect(await service.load(), {CatalogType.ngc});
    });
  });
}
