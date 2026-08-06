import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/astro_season.dart';
import '../../../core/constants/catalog_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/season_planner_filter_theme.dart';
import '../../../data/models/season_planner_item.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/shooting_record_repository.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../services/equipment/equipment_recommendation_service.dart';
import '../../../services/exposure_policy.dart';
import '../../../services/base_exposure_settings_service.dart';
import '../../../services/metadata_service.dart';
import '../../../services/object_imaging_profile_provider.dart';
import '../../../services/photo_registration_service.dart';
import '../../../services/season_planner_filter_service.dart';
import '../../../services/season_planner_service.dart';
import '../../../shared/widgets/catalog_object_card.dart';
import '../../../shared/widgets/responsive_filter_chips.dart';
import '../../catalog/view/catalog_detail_screen.dart';
import '../../catalog/viewmodel/catalog_detail_view_model.dart';
import '../../catalog/viewmodel/catalog_view_model.dart';
import '../../gallery/viewmodel/gallery_view_model.dart';
import '../../home/viewmodel/home_view_model.dart';
import '../../stats/viewmodel/stats_view_model.dart';
import '../viewmodel/season_planner_view_model.dart';

int _gridCrossAxisCount(double width) {
  if (width >= 840) return 4;
  if (width >= 600) return 3;
  return 2;
}

/// 계절/월별 촬영 대상 전용 화면.
class SeasonPlannerScreen extends StatelessWidget {
  const SeasonPlannerScreen({super.key});

  static Future<void> open(BuildContext context) {
    final catalogRepo = context.read<CatalogRepository>();
    final shootingRepo = context.read<ShootingRecordRepository>();
    final filterService = context.read<SeasonPlannerFilterService>();

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => SeasonPlannerViewModel(
            catalogRepo,
            shootingRepo,
            filterService,
          )..load(),
          child: const SeasonPlannerScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<SeasonPlannerViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('계절별 촬영 대상'),
      ),
      body: viewModel.isLoading
          ? const Center(child: CircularProgressIndicator())
          : viewModel.errorMessage != null
              ? Center(child: Text(viewModel.errorMessage!))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PlannerHeaderPanel(viewModel: viewModel),
                    Expanded(
                      child: viewModel.items.isEmpty
                          ? const Center(
                              child: Text(
                                '조건에 맞는 촬영 대상이 없습니다.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : _SeasonObjectGrid(viewModel: viewModel),
                    ),
                  ],
                ),
    );
  }
}

class _PlannerHeaderPanel extends StatelessWidget {
  const _PlannerHeaderPanel({required this.viewModel});

  final SeasonPlannerViewModel viewModel;

  static String _catalogLabel(CatalogType type) {
    switch (type) {
      case CatalogType.messier:
        return 'Messier';
      case CatalogType.ngc:
        return 'NGC';
      case CatalogType.ic:
        return 'IC';
      case CatalogType.caldwell:
        return 'Caldwell';
      case CatalogType.sh2:
        return 'Sh2';
      case CatalogType.rcw:
        return 'RCW';
      case CatalogType.vdb:
        return 'vdB';
      default:
        return type.label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<SeasonPlannerViewModel>();
    final selected = viewModel.catalogFilters;
    final periodLabel = viewModel.viewMode == SeasonPlannerViewMode.bySeason
        ? '${viewModel.selectedSeason.label} (${viewModel.selectedSeason.subtitle})'
        : SeasonPlannerService.monthLabels[viewModel.selectedMonth - 1];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingLg,
        AppTheme.spacingSm,
        AppTheme.spacingLg,
        AppTheme.spacingSm,
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FullWidthSegmentedButton<SeasonPlannerViewMode>(
                segments: const [
                  ButtonSegment(
                    value: SeasonPlannerViewMode.bySeason,
                    label: Text('계절별'),
                    icon: Icon(Icons.wb_sunny_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: SeasonPlannerViewMode.byMonth,
                    label: Text('월별'),
                    icon: Icon(Icons.calendar_month_outlined, size: 16),
                  ),
                ],
                selected: {viewModel.viewMode},
                onSelectionChanged: (selection) {
                  vm.setViewMode(selection.first);
                },
              ),
              const SizedBox(height: AppTheme.spacingSm),
              if (viewModel.viewMode == SeasonPlannerViewMode.bySeason)
                _SeasonSelector(viewModel: viewModel)
              else
                _MonthSelector(viewModel: viewModel),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppTheme.spacingSm),
                child: Divider(
                  height: 1,
                  color: Color(0x33FFFFFF),
                ),
              ),
              Row(
                children: [
                  const Text(
                    '필터',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (viewModel.hasCatalogFilter)
                    TextButton(
                      onPressed: vm.clearCatalogFilters,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text(
                        '카탈로그 초기화',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              ResponsiveFilterChipGrid(
                singleRow: true,
                itemCount:
                    1 + SeasonPlannerService.plannerCatalogTypes.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ExpandedFilterChip(
                      compact: true,
                      label: const Text(
                        '미촬영만',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10),
                      ),
                      selected: viewModel.uncapturedOnly,
                      onSelected: vm.setUncapturedOnly,
                      backgroundColor: SeasonPlannerFilterTheme
                          .colorsFor(selected: viewModel.uncapturedOnly)
                          .background,
                      selectedColor: SeasonPlannerFilterTheme
                          .colorsFor(selected: true)
                          .background,
                      side: BorderSide(
                        color: SeasonPlannerFilterTheme
                            .colorsFor(selected: viewModel.uncapturedOnly)
                            .border,
                        width: viewModel.uncapturedOnly ? 1.5 : 1,
                      ),
                      labelStyle: TextStyle(
                        color: SeasonPlannerFilterTheme
                            .colorsFor(selected: viewModel.uncapturedOnly)
                            .label,
                        fontSize: 12,
                        fontWeight: viewModel.uncapturedOnly
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    );
                  }

                  final catalog =
                      SeasonPlannerService.plannerCatalogTypes[index - 1];
                  final isChecked =
                      selected.isEmpty || selected.contains(catalog);
                  final colors =
                      SeasonPlannerFilterTheme.colorsFor(selected: isChecked);
                  return ExpandedFilterChip(
                    compact: true,
                    label: Text(
                      _catalogLabel(catalog),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10),
                    ),
                    selected: isChecked,
                    onSelected: (_) => vm.toggleCatalogFilter(catalog),
                    backgroundColor: colors.background,
                    selectedColor: colors.background,
                    side: BorderSide(
                      color: colors.border,
                      width: isChecked ? 1.5 : 1,
                    ),
                    labelStyle: TextStyle(
                      color: colors.label,
                      fontSize: 12,
                      fontWeight:
                          isChecked ? FontWeight.w600 : FontWeight.w500,
                    ),
                  );
                },
              ),
              const SizedBox(height: AppTheme.spacingSm),
              Text(
                '$periodLabel · 추천 ${viewModel.items.length}개'
                '${viewModel.uncapturedOnly ? '' : ' · 미촬영 ${viewModel.uncapturedCount}개'}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({required this.viewModel});

  final SeasonPlannerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ResponsiveFilterChipGrid(
      singleRow: true,
      itemCount: AstroSeason.values.length,
      itemBuilder: (context, index) {
        final season = AstroSeason.values[index];
        final selected = viewModel.selectedSeason == season;
        return ExpandedFilterChip(
          compact: true,
          label: Text(
            '${season.label} ${season.subtitle}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10),
          ),
          selected: selected,
          onSelected: (_) {
            context.read<SeasonPlannerViewModel>().selectSeason(season);
          },
          labelStyle: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        );
      },
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.viewModel});

  final SeasonPlannerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ResponsiveFilterChipGrid(
      singleRow: true,
      itemCount: 12,
      itemBuilder: (context, index) {
        final month = index + 1;
        final selected = viewModel.selectedMonth == month;
        final isCurrent = month == DateTime.now().month;
        return ExpandedFilterChip(
          compact: true,
          label: Text(
            SeasonPlannerService.monthLabels[index],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9),
          ),
          selected: selected,
          avatar: isCurrent
              ? const Icon(Icons.circle, size: 8, color: AppColors.solar)
              : null,
          onSelected: (_) {
            context.read<SeasonPlannerViewModel>().selectMonth(month);
          },
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        );
      },
    );
  }
}

class _SeasonObjectGrid extends StatelessWidget {
  const _SeasonObjectGrid({required this.viewModel});

  final SeasonPlannerViewModel viewModel;

  Future<void> _openDetail(BuildContext context, SeasonPlannerItem item) async {
    final catalogRepo = context.read<CatalogRepository>();
    final shootingRepo = context.read<ShootingRecordRepository>();
    final metadataSvc = context.read<MetadataService>();
    final registrationSvc = context.read<PhotoRegistrationService>();
    final equipmentRepo = context.read<EquipmentRepository>();
    final equipmentRecSvc = context.read<EquipmentRecommendationService>();
    final baseExposureSettingsService =
        context.read<BaseExposureSettingsService>();
    final profileProvider = context.read<ObjectImagingProfileProvider>();
    final exposurePolicy = context.read<ExposurePolicy>();
    final catalogVm = context.read<CatalogViewModel>();
    final galleryVm = context.read<GalleryViewModel>();
    final homeVm = context.read<HomeViewModel>();
    final statsVm = context.read<StatsViewModel>();
    final seasonVm = context.read<SeasonPlannerViewModel>();

    final navigationObjects =
        viewModel.items.map((entry) => entry.object).toList();

    final detailVm = CatalogDetailViewModel(
      item.object,
      shootingRepo,
      catalogRepo,
      registrationSvc,
      metadataSvc,
      equipmentRepo,
      equipmentRecSvc,
      baseExposureSettingsService,
      profileProvider,
      exposurePolicy,
      navigationObjects: navigationObjects,
    );

    final dataChanged = await Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ChangeNotifierProvider.value(
              value: detailVm,
              child: const CatalogDetailScreen(),
            ),
          ),
        )
        .then((_) => detailVm.dataChanged);
    detailVm.dispose();

    if (!context.mounted) return;
    if (!dataChanged) return;

    unawaited(
      Future.wait([
        seasonVm.load(),
        catalogVm.load(silent: true),
        galleryVm.load(),
        homeVm.load(),
        statsVm.load(),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridCrossAxisCount(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppTheme.spacingSm,
            mainAxisSpacing: AppTheme.spacingSm,
            childAspectRatio: 1.1,
          ),
          itemCount: viewModel.items.length,
          itemBuilder: (context, index) {
            final item = viewModel.items[index];
            const seasonService = SeasonPlannerService();
            final equipmentChips =
                context.watch<CatalogViewModel>().equipmentChipsFor(
                      item.object.id,
                    );
            return CatalogObjectCard(
              object: item.object,
              thumbnailPath: item.thumbnailPath,
              equipmentChips: equipmentChips,
              footerText: '최적 ${seasonService.peakMonthLabel(item.object)}',
              onTap: () => _openDetail(context, item),
            );
          },
        );
      },
    );
  }
}
