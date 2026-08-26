import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../viewmodel/stats_view_model.dart';
import 'widgets/catalog_category_progress_card.dart';
import 'widgets/monthly_combo_chart_card.dart';
import 'widgets/monthly_stats_bottom_sheet.dart';
import 'widgets/object_type_donut_card.dart';
import 'widgets/stats_kpi_grid.dart';
import 'widgets/top_targets_chart_card.dart';
import 'widgets/year_achievement_card.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<StatsViewModel>();
    final dashboard = viewModel.dashboard;
    final chartYear = viewModel.chartYear;

    return Scaffold(
      appBar: AppBar(title: const Text('촬영 결과 분석')),
      body: viewModel.isLoading
          ? const Center(child: CircularProgressIndicator())
          : viewModel.errorMessage != null
          ? Center(child: Text(viewModel.errorMessage!))
          : dashboard == null
          ? const Center(
              child: Text(
                '통계 데이터를 불러올 수 없습니다.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: viewModel.load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingLg,
                  AppTheme.spacingSm,
                  AppTheme.spacingLg,
                  AppTheme.spacingLg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatsKpiGrid(kpi: dashboard.kpi),
                    const SizedBox(height: AppTheme.spacingSm),
                    MonthlyComboChartCard(
                      monthlyStats: dashboard.monthlyStats,
                      currentMonth: dashboard.currentMonth,
                      year: chartYear,
                      onMonthDetail: (month) {
                        final detail = viewModel.monthlyDetail(
                          year: chartYear,
                          month: month,
                        );
                        MonthlyStatsBottomSheet.show(context, detail);
                      },
                    ),
                    const SizedBox(height: AppTheme.spacingMd),
                    TopTargetsChartCard(targets: dashboard.topTargets),
                    const SizedBox(height: AppTheme.spacingMd),
                    ObjectTypeDonutCard(breakdown: dashboard.typeBreakdown),
                    const SizedBox(height: AppTheme.spacingMd),
                    CatalogCategoryProgressCard(
                      progress: viewModel.categoryProgress,
                    ),
                    const SizedBox(height: AppTheme.spacingMd),
                    YearAchievementCard(
                      summary: viewModel.selectedYearAchievement,
                      availableYears: viewModel.availableAchievementYears,
                      selectedYear: viewModel.selectedAchievementYear,
                      onYearChanged: viewModel.selectAchievementYear,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
