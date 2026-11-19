import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/astro_season.dart';
import '../../../core/constants/catalog_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/pc_design.dart';
import '../../../core/theme/season_planner_filter_theme.dart';
import '../../../data/models/season_planner_item.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/gallery_shooting_record_repository_adapter.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/observation_site_repository.dart';
import '../../../services/equipment/equipment_recommendation_service.dart';
import '../../../services/exposure_policy.dart';
import '../../../services/base_exposure_settings_service.dart';
import '../../../services/metadata_service.dart';
import '../../../services/object_imaging_profile_provider.dart';
import '../../../services/observation_condition_service.dart';
import '../../../services/photo_registration_service.dart';
import '../../../services/target_imaging_availability_service.dart';
import '../../../services/season_planner_filter_service.dart';
import '../../../services/season_planner_service.dart';
import '../../../services/catalog_capture_projection_service.dart';
import '../../../shared/widgets/catalog_display_scope_selector.dart';
import '../../../shared/widgets/catalog_object_card.dart';
import '../../../shared/widgets/mobile_content_layout.dart';
import '../../../shared/widgets/pc_card_grid.dart';
import '../../../shared/widgets/responsive_filter_chips.dart';
import '../../catalog/view/catalog_detail_screen.dart';
import '../../catalog/viewmodel/catalog_detail_view_model.dart';
import '../../catalog/viewmodel/catalog_view_model.dart';
import '../../gallery/viewmodel/gallery_view_model.dart';
import '../../home/viewmodel/home_view_model.dart';
import '../../stats/viewmodel/stats_view_model.dart';
import '../viewmodel/season_planner_view_model.dart';

/// 계절/월별 촬영 대상 전용 화면.
class SeasonPlannerScreen extends StatelessWidget {
  const SeasonPlannerScreen({super.key, this.fixedViewMode = false});

  final bool fixedViewMode;

  static Future<void> open(
    BuildContext context, {
    SeasonPlannerViewMode initialViewMode = SeasonPlannerViewMode.bySeason,
    int? initialMonth,
    bool fixedViewMode = false,
  }) {
    final catalogRepo = context.read<CatalogRepository>();
    final shootingRepo = context.read<GalleryShootingRecordRepositoryAdapter>();
    final filterService = context.read<SeasonPlannerFilterService>();

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => SeasonPlannerViewModel(
            catalogRepo,
            shootingRepo,
            filterService,
            initialViewMode: initialViewMode,
            initialMonth: initialMonth,
          )..load(),
          child: SeasonPlannerScreen(fixedViewMode: fixedViewMode),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      MobileContentTheme(builder: _buildContent);

  Widget _buildContent(BuildContext context) {
    final viewModel = context.watch<SeasonPlannerViewModel>();
    final mobile = PcDesign.isMobileContent(context);
    final header = _PlannerHeaderPanel(
      viewModel: viewModel,
      fixedViewMode: fixedViewMode,
    );
    final grid = viewModel.items.isEmpty
        ? Center(
            child: Text(
              '조건에 맞는 촬영 대상이 없습니다.',
              style: TextStyle(
                color: mobile ? PcDesign.muted : AppColors.textSecondary,
              ),
            ),
          )
        : _SeasonObjectGrid(viewModel: viewModel);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          (fixedViewMode || mobile) &&
                  viewModel.viewMode == SeasonPlannerViewMode.byMonth
              ? '월별 계획'
              : '계절별 촬영 대상',
        ),
      ),
      body: viewModel.isLoading
          ? const Center(child: CircularProgressIndicator())
          : viewModel.errorMessage != null
          ? Center(child: Text(viewModel.errorMessage!))
          : mobile
          ? MobileContentLayout(header: [header], body: grid)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(child: grid),
              ],
            ),
    );
  }
}

class _PlannerHeaderPanel extends StatelessWidget {
  const _PlannerHeaderPanel({
    required this.viewModel,
    required this.fixedViewMode,
  });

  final SeasonPlannerViewModel viewModel;
  final bool fixedViewMode;

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
    final pc = PcDesign.isStyled(context);
    final mobile = PcDesign.isMobileContent(context);
    final muted = mobile ? PcDesign.muted : AppColors.textSecondary;
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
        color: pc ? PcDesign.card : AppColors.surface,
        borderRadius: mobile
            ? null
            : BorderRadius.circular(AppTheme.cardRadius),
        shape: mobile
            ? const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(AppTheme.cardRadius),
                ),
                side: BorderSide(color: PcDesign.border),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!fixedViewMode)
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
              if (!fixedViewMode) const SizedBox(height: AppTheme.spacingSm),
              if (viewModel.viewMode == SeasonPlannerViewMode.bySeason)
                _SeasonSelector(viewModel: viewModel)
              else
                _MonthSelector(viewModel: viewModel),
              const SizedBox(height: AppTheme.spacingSm),
              CatalogDisplayScopeSelector(
                scope: viewModel.displayScope,
                onChanged: vm.selectDisplayScope,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppTheme.spacingSm,
                ),
                child: Divider(
                  height: 1,
                  color: pc ? PcDesign.border : const Color(0x33FFFFFF),
                ),
              ),
              Row(
                children: [
                  Text(
                    '필터',
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (viewModel.hasCatalogFilter)
                    TextButton(
                      onPressed: vm.clearCatalogFilters,
                      style: mobile
                          ? null
                          : TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
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
                singleRow: !mobile,
                minColumnWidth: mobile ? 73 : null,
                maxColumns: mobile ? 4 : null,
                itemCount: 1 + SeasonPlannerService.plannerCatalogTypes.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final colors = SeasonPlannerFilterTheme.colorsFor(
                      selected: viewModel.uncapturedOnly,
                      pc: pc,
                    );
                    return ExpandedFilterChip(
                      compact: true,
                      label: Text(
                        '미촬영만',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: mobile ? 12 : 10),
                      ),
                      selected: viewModel.uncapturedOnly,
                      onSelected: vm.setUncapturedOnly,
                      backgroundColor: colors.background,
                      selectedColor: SeasonPlannerFilterTheme.colorsFor(
                        selected: true,
                        pc: pc,
                      ).background,
                      side: BorderSide(
                        color: colors.border,
                        width: viewModel.uncapturedOnly ? 1.5 : 1,
                      ),
                      labelStyle: TextStyle(
                        color: colors.label,
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
                  final colors = SeasonPlannerFilterTheme.colorsFor(
                    selected: isChecked,
                    pc: pc,
                  );
                  return ExpandedFilterChip(
                    compact: true,
                    label: Text(
                      _catalogLabel(catalog),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: mobile ? 12 : 10),
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
                      fontWeight: isChecked ? FontWeight.w600 : FontWeight.w500,
                    ),
                  );
                },
              ),
              const SizedBox(height: AppTheme.spacingSm),
              Text(
                '$periodLabel · 추천 ${viewModel.items.length}개'
                '${viewModel.uncapturedOnly ? '' : ' · 미촬영 ${viewModel.uncapturedCount}개'}',
                style: TextStyle(color: muted, fontSize: mobile ? 12 : 11),
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
    final mobile = PcDesign.isMobileContent(context);
    return ResponsiveFilterChipGrid(
      singleRow: !mobile,
      minColumnWidth: mobile ? 104 : null,
      maxColumns: mobile ? 4 : null,
      itemCount: AstroSeason.values.length,
      itemBuilder: (context, index) {
        final season = AstroSeason.values[index];
        final selected = viewModel.selectedSeason == season;
        return ExpandedFilterChip(
          compact: true,
          label: Text(
            '${season.label} ${season.subtitle}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: mobile ? 12 : 10),
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
    final mobile = PcDesign.isMobileContent(context);
    return ResponsiveFilterChipGrid(
      singleRow: !mobile,
      minColumnWidth: mobile ? 54 : null,
      maxColumns: mobile ? 6 : null,
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
            style: TextStyle(fontSize: mobile ? 12 : 9),
          ),
          selected: selected,
          avatar: isCurrent
              ? Icon(
                  Icons.circle,
                  size: 8,
                  color: PcDesign.isStyled(context)
                      ? PcDesign.secondary
                      : AppColors.solar,
                )
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
    final shootingRepo = context.read<GalleryShootingRecordRepositoryAdapter>();
    final metadataSvc = context.read<MetadataService>();
    final registrationSvc = context.read<PhotoRegistrationService>();
    final equipmentRepo = context.read<EquipmentRepository>();
    final equipmentRecSvc = context.read<EquipmentRecommendationService>();
    final baseExposureSettingsService = context
        .read<BaseExposureSettingsService>();
    final profileProvider = context.read<ObjectImagingProfileProvider>();
    final exposurePolicy = context.read<ExposurePolicy>();
    final catalogVm = context.read<CatalogViewModel>();
    final galleryVm = context.read<GalleryViewModel>();
    final homeVm = context.read<HomeViewModel>();
    final statsVm = context.read<StatsViewModel>();
    final seasonVm = context.read<SeasonPlannerViewModel>();

    final navigationObjects = viewModel.items
        .map((entry) => entry.object)
        .toList();

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
      captureProjection: context.read<CatalogCaptureProjectionService>(),
      observationSiteRepository: context.read<ObservationSiteRepository>(),
      availabilityService: context.read<TargetImagingAvailabilityService>(),
      observationConditionService: context.read<ObservationConditionService>(),
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
        const padding = EdgeInsets.all(AppTheme.spacingLg);
        return GridView.builder(
          padding: padding,
          gridDelegate: PcDesign.isActive(context)
              ? PcCardGrid.delegate(
                  contentWidth: constraints.maxWidth - padding.horizontal,
                  childAspectRatio: 1.1,
                )
              : MobileContentGrid.delegate(
                  context,
                  contentWidth: constraints.maxWidth - padding.horizontal,
                  childAspectRatio: 1.1,
                  minimumCardHeight: 176,
                ),
          itemCount: viewModel.items.length,
          itemBuilder: (context, index) {
            final item = viewModel.items[index];
            const seasonService = SeasonPlannerService();
            final equipmentChips = context
                .watch<CatalogViewModel>()
                .equipmentChipsFor(item.object.id);
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
