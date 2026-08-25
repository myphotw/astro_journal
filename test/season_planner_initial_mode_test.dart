import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/season/viewmodel/season_planner_view_model.dart';
import 'package:astro_journal/services/season_planner_filter_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _CatalogRepository implements CatalogRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShootingRecordRepository implements ShootingRecordRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
}
