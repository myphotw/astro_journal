import 'package:astro_journal/core/constants/astro_season.dart';
import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/famous_celestial_objects.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/season/viewmodel/season_planner_view_model.dart';
import 'package:astro_journal/services/season_planner_filter_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _CatalogRepository implements CatalogRepository {
  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => [
    _target('M42', '05h', CatalogType.messier),
    _target('M31', '01h', CatalogType.messier),
    _target('NGC40', '05h', CatalogType.ngc),
    _target('M13', '17h', CatalogType.messier),
    _target('solar_1', '05h', CatalogType.solar),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShootingRecordRepository implements ShootingRecordRepository {
  @override
  Future<List<ShootingRecord>> getAll() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FilterService extends SeasonPlannerFilterService {
  @override
  Future<Set<CatalogType>> load() async => {};

  @override
  Future<void> save(Set<CatalogType> catalogFilters) async {}
}

CatalogObject _target(String id, String ra, CatalogType catalog) => CatalogObject(
  id: id,
  number: 1,
  catalog: catalog,
  name: id,
  type: '성운',
  constellation: '-',
  ra: ra,
  dec: '+00°00',
  magnitude: '8',
);

void main() {
  test('monthly entry opens the shared planner in monthly mode', () {
    final viewModel = SeasonPlannerViewModel(
      _CatalogRepository(),
      _ShootingRecordRepository(),
      SeasonPlannerFilterService(),
      initialViewMode: SeasonPlannerViewMode.byMonth,
      initialMonth: 8,
    );

    expect(viewModel.viewMode, SeasonPlannerViewMode.byMonth);
    expect(viewModel.selectedMonth, 8);
  });

  test('seasonal entry keeps the shared planner in seasonal mode', () {
    final viewModel = SeasonPlannerViewModel(
      _CatalogRepository(),
      _ShootingRecordRepository(),
      SeasonPlannerFilterService(),
    );

    expect(viewModel.viewMode, SeasonPlannerViewMode.bySeason);
  });

  test('monthly and seasonal scopes start famous and stay independent', () async {
    final vm = SeasonPlannerViewModel(
      _CatalogRepository(),
      _ShootingRecordRepository(),
      _FilterService(),
      initialViewMode: SeasonPlannerViewMode.byMonth,
      initialMonth: 12,
    );
    addTearDown(vm.dispose);
    Iterable<String> itemIds() => vm.items.map((item) => item.object.id);
    await vm.load();
    expect(vm.displayScope, CatalogDisplayScope.famous);
    expect(itemIds(), ['M42']);

    vm.selectDisplayScope(CatalogDisplayScope.all);
    expect(itemIds(), unorderedEquals(['M42', 'NGC40']));
    vm.setViewMode(SeasonPlannerViewMode.bySeason);
    vm.selectSeason(AstroSeason.winter);
    await Future<void>.delayed(Duration.zero);
    expect(vm.displayScope, CatalogDisplayScope.famous);
    expect(itemIds(), ['M42']);

    vm.selectDisplayScope(CatalogDisplayScope.all);
    expect(itemIds(), unorderedEquals(['M42', 'NGC40']));
    vm.toggleCatalogFilter(CatalogType.ngc);
    await Future<void>.delayed(Duration.zero);
    expect(itemIds(), ['M42']);

    vm.selectDisplayScope(CatalogDisplayScope.famous);
    vm.setViewMode(SeasonPlannerViewMode.byMonth);
    vm.clearCatalogFilters();
    await Future<void>.delayed(Duration.zero);
    expect(vm.displayScope, CatalogDisplayScope.all);
    expect(itemIds(), unorderedEquals(['M42', 'NGC40']));
  });
}
