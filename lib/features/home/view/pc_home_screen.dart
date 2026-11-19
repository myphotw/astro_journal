import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/formatters/catalog_object_display_formatter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/observation_status.dart';
import '../../../data/models/imaging_suitability_assessment.dart';
import '../../../data/models/recommendation_result.dart';
import '../../../data/models/scheduler_models.dart';
import '../../../services/observation_score_service.dart';
import '../../../shared/widgets/catalog_object_image.dart';
import '../../../shared/widgets/observatory_ui.dart';
import '../../../shared/widgets/pc_observatory_dialog.dart';
import '../../../shared/widgets/pc_scroll_edge_buttons.dart';
import '../../observation_site/view/observation_site_detail_screen.dart';
import '../../settings/view/observation_site_edit_screen.dart';
import '../../settings/view/observation_site_list_screen.dart';
import '../viewmodel/astronomy_events_view_model.dart';
import '../viewmodel/home_view_model.dart';
import 'home_screen.dart';
import 'widgets/astronomy_events_section.dart';
import 'widgets/home_observation_context_controls.dart';
import 'widgets/pc_dashboard_layout.dart';
import 'widgets/pc_home_colors.dart';
import 'widgets/pc_recent_photos_panel.dart';
import 'widgets/shooting_plan_action_button.dart';

class PcHomeScreen extends StatefulWidget {
  const PcHomeScreen({super.key});

  @override
  State<PcHomeScreen> createState() => _PcHomeScreenState();
}

class _PcHomeScreenState extends State<PcHomeScreen> {
  HomeViewModel? _homeViewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<HomeViewModel>();
    if (identical(_homeViewModel, next)) return;
    _homeViewModel = next;
    scheduleMicrotask(() => unawaited(next.finishDeferredHeavyWork()));
  }

  Future<void> _refresh() async {
    final events = context.read<AstronomyEventsViewModel?>();
    await Future.wait<void>([
      context.read<HomeViewModel>().refresh(),
      if (events != null) events.refresh(),
    ]);
  }

  Future<void> _selectCurrentSite() => context
      .read<HomeViewModel>()
      .activeObservationSiteViewModel
      .selectCurrentLocation();

  Future<void> _selectSavedSite(String id) async {
    final active = context.read<HomeViewModel>().activeObservationSiteViewModel;
    for (final site in active.sites) {
      if (site.id != id) continue;
      await active.selectSavedSite(site);
      return;
    }
  }

  void _openActiveSiteDetail() {
    final home = context.read<HomeViewModel>();
    final active = home.activeObservationSiteViewModel;
    final siteId = active.active.selectedSiteId;
    if (siteId == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ObservationSiteDetailScreen(
          siteId: siteId,
          homeViewModel: home,
          activeViewModel: active,
        ),
      ),
    );
  }

  Future<void> _manageSites() async {
    final home = context.read<HomeViewModel>();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ObservationSiteListScreen()),
    );
    if (!mounted) return;
    await home.activeObservationSiteViewModel.load(force: true);
  }

  Future<void> _saveCurrentLocation() async {
    final home = context.read<HomeViewModel>();
    final active = home.activeObservationSiteViewModel.active;
    if (active.latitude == null || active.longitude == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ObservationSiteEditScreen(
          initialLatitude: active.latitude,
          initialLongitude: active.longitude,
        ),
      ),
    );
    if (changed == true && mounted) {
      await home.activeObservationSiteViewModel.load(force: true);
    }
  }

  Future<void> _showObservationDetail(ObservationCondition condition) =>
      showPcObservatoryDialog<void>(
        context: context,
        title: '오늘 밤 관측 가이드',
        size: PcPopupSize.large,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: _PcObservationAssessment(condition: condition),
          ),
        ),
      );

  Future<void> _showWeatherDetail(List<TonightObservationSlot> slots) =>
      showPcObservatoryDialog<void>(
        context: context,
        title: '시간대별 기상정보',
        size: PcPopupSize.extraLarge,
        scrollable: false,
        child: LayoutBuilder(
          builder: (context, constraints) => _PcWeatherTable(
            slots: slots,
            maxBodyHeight: (constraints.maxHeight - 36)
                .clamp(38.0, double.infinity).toDouble(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final home = context.read<HomeViewModel>();
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: PcHomeColors.accent,
          secondary: PcHomeColors.secondaryAccent,
          surface: PcHomeColors.panel,
          onSurface: PcHomeColors.text,
        ),
        textTheme: theme.textTheme.apply(
          bodyColor: PcHomeColors.text,
          displayColor: PcHomeColors.text,
        ),
        iconTheme: theme.iconTheme.copyWith(color: PcHomeColors.muted),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: PcHomeColors.secondaryAccent,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: PcHomeColors.background,
        body: ListenableBuilder(
          listenable: home,
          builder: (context, _) {
            if (home.isLoading && home.observationCondition == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (home.errorMessage != null && home.observationCondition == null) {
              return _PcHomeFailure(
                message: home.errorMessage!,
                onRetry: _refresh,
              );
            }
            return _buildDashboard(home);
          },
        ),
      ),
    );
  }

  Widget _buildDashboard(HomeViewModel home) {
    final condition = home.observationCondition;
    final weather = condition?.weather;
    final weatherSlots = condition?.tonightSlots ?? const <TonightObservationSlot>[];
    final activeSite = home.activeObservationSiteViewModel.active;
    final selectedEquipmentId = activeSite.effectiveEquipmentId;
    String? selectedEquipmentName;
    for (final equipment in home.activeEquipment) {
      if (equipment.id == selectedEquipmentId) {
        selectedEquipmentName = equipment.name;
        break;
      }
    }

    return PcHomeDashboardView(
      onRefresh: _refresh,
      contextControls: HomeObservationContextControls(
        stackOnNarrow: true,
        accentColor: PcHomeColors.accent,
        siteViewModel: home.activeObservationSiteViewModel,
        equipment: home.activeEquipment,
        selectedEquipmentId: selectedEquipmentId,
        selectedEquipmentName: selectedEquipmentName,
        trackingMode: home.trackingMode,
        onSelectCurrentLocation: _selectCurrentSite,
        onSelectSite: _selectSavedSite,
        onOpenSiteDetail: _openActiveSiteDetail,
        onManageSites: _manageSites,
        onSaveCurrentLocation: _saveCurrentLocation,
        onEquipmentChanged: home.setEquipment,
        onTrackingChanged: home.setTrackingMode,
        activeWeather: condition?.weather,
        isWeatherLoading: home.isWeatherLoading,
        currentLocationBortle: home.lastSessionContext?.bortle,
      ),
      astronomyPanel: _PcAstronomyPanel(
        condition: condition,
        bortle: home.lastSessionContext?.bortle,
      ),
      hourlyWeatherPanel: _PcHourlyWeatherPanel(
        condition: condition,
        isLoading: home.isWeatherLoading,
      ),
      recommendationPanel: _PcRecommendationPanel(home: home),
      schedulePanel: _PcSchedulePanel(
        home: home,
        onDetail: () => unawaited(showPcHomeShootingOrderEditor(context, home)),
      ),
      eventsFooter: const AstronomyEventsSection(compactList: true),
      recentPhotos: const PcRecentPhotosPanel(),
      siteName: activeSite.displayName,
      equipmentName: selectedEquipmentName ?? '자동 선택',
      trackingModeLabel: home.trackingMode == TrackingMode.eq ? 'EQ' : 'Alt-Az',
      weatherSummary: weather == null
          ? (home.isWeatherLoading ? '날씨 확인 중' : '날씨 정보 없음')
          : '${weather.description} · '
              '${weather.temperature.toStringAsFixed(0)}°C',
      onObservationDetail: condition == null
          ? null
          : () => unawaited(_showObservationDetail(condition)),
      onWeatherDetail: weatherSlots.isEmpty
          ? null
          : () => unawaited(_showWeatherDetail(weatherSlots)),
    );
  }
}

/// Presentation-only frame used by the Windows home dashboard.
///
/// Keeping the responsive frame independent from [HomeViewModel] makes its
/// overflow contract testable without duplicating any astronomy calculation.
class PcHomeDashboardView extends StatefulWidget {
  const PcHomeDashboardView({
    super.key,
    required this.contextControls,
    required this.astronomyPanel,
    required this.hourlyWeatherPanel,
    required this.recommendationPanel,
    required this.schedulePanel,
    required this.eventsFooter,
    this.onRefresh,
    this.recentPhotos,
    this.siteName = '현재 위치',
    this.equipmentName = '자동 선택',
    this.trackingModeLabel = 'Alt-Az',
    this.weatherSummary,
    this.onObservationDetail,
    this.onWeatherDetail,
  });

  final Widget contextControls;
  final Widget astronomyPanel;
  final Widget hourlyWeatherPanel;
  final Widget recommendationPanel;
  final Widget schedulePanel;
  final Widget eventsFooter;
  final Future<void> Function()? onRefresh;
  final Widget? recentPhotos;
  final String siteName;
  final String equipmentName;
  final String trackingModeLabel;
  final String? weatherSummary;
  final VoidCallback? onObservationDetail;
  final VoidCallback? onWeatherDetail;

  @override
  State<PcHomeDashboardView> createState() => _PcHomeDashboardViewState();
}

class _PcHomeDashboardViewState extends State<PcHomeDashboardView> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) => PcDashboardLayout(
        viewport: viewport,
        child: Builder(builder: _buildDashboard),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final layout = PcDashboardLayout.maybeOf(context)!;
    return CustomScrollView(
      key: const Key('pc-home-scroll-view'),
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _PcHomeHero(
            siteName: widget.siteName,
            weatherSummary: widget.weatherSummary,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: layout.horizontalPadding,
              vertical: layout.sectionGap,
            ),
            child: Row(
              key: const Key('pc-home-observation-context'),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: const Key('pc-home-context-controls'),
                    child: widget.contextControls,
                  ),
                ),
                if (widget.onRefresh != null)
                  IconButton(
                    key: const Key('pc-home-refresh'),
                    tooltip: '홈 새로고침',
                    onPressed: () => unawaited(widget.onRefresh!()),
                    icon: const Icon(Icons.refresh_outlined),
                    iconSize: 19,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
        SliverLayoutBuilder(
          builder: (context, constraints) {
            // Use the total viewport, not the remaining paint extent, so
            // scrolling the page never changes the cards' heights.
            final heights = layout.rowHeights(
              constraints.viewportMainAxisExtent -
                  constraints.precedingScrollExtent -
                  2 * layout.sectionGap,
            );
            return SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.horizontalPadding,
                  0,
                  layout.horizontalPadding,
                  layout.sectionGap,
                ),
                child: Column(
                  children: [
                    _PcHomeResponsiveColumns(
                      rowHeight: heights.upper,
                      astronomyPanel: widget.astronomyPanel,
                      weatherPanel: widget.hourlyWeatherPanel,
                      recommendationPanel: widget.recommendationPanel,
                      schedulePanel: widget.schedulePanel,
                      onObservationDetail: widget.onObservationDetail,
                      onWeatherDetail: widget.onWeatherDetail,
                    ),
                    SizedBox(height: layout.sectionGap),
                    _buildLowerRow(layout, heights.lower),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLowerRow(PcDashboardLayout layout, double rowHeight) {
    final photos = widget.recentPhotos;
    final events = ObservatoryPanel(
      key: const Key('pc-home-astronomy-events'),
      padding: EdgeInsets.all(layout.panelPadding),
      backgroundColor: PcHomeColors.panel,
      borderColor: PcHomeColors.border,
      child: widget.eventsFooter,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (photos == null) return SizedBox(height: rowHeight, child: events);
        if (constraints.maxWidth < 1100) {
          return Column(
            children: [
              SizedBox(height: rowHeight, child: photos),
              const SizedBox(height: AppTheme.spacingMd),
              SizedBox(height: rowHeight, child: events),
            ],
          );
        }
        return SizedBox(
          height: rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: photos),
              SizedBox(width: layout.panelPadding),
              Expanded(flex: 2, child: events),
            ],
          ),
        );
      },
    );
  }
}

class _PcHomeResponsiveColumns extends StatelessWidget {
  const _PcHomeResponsiveColumns({
    required this.rowHeight,
    required this.astronomyPanel,
    required this.weatherPanel,
    required this.recommendationPanel,
    required this.schedulePanel,
    required this.onObservationDetail,
    required this.onWeatherDetail,
  });

  final double rowHeight;
  final Widget astronomyPanel;
  final Widget weatherPanel;
  final Widget recommendationPanel;
  final Widget schedulePanel;
  final VoidCallback? onObservationDetail;
  final VoidCallback? onWeatherDetail;

  Widget _statusPanel(PcDashboardLayout layout) => ObservatoryPanel(
    padding: EdgeInsets.all(layout.panelPadding),
    backgroundColor: PcHomeColors.panel,
    borderColor: PcHomeColors.border,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ObservatorySectionHeader(
          title: '관측 상태 및 지수',
          icon: Icons.travel_explore_outlined,
          iconColor: PcHomeColors.muted,
          titleColor: PcHomeColors.text,
          trailing: onObservationDetail == null
              ? null
              : TextButton(
                  onPressed: onObservationDetail,
                  child: const Text('자세히 보기 ›'),
                ),
        ),
        const Divider(height: AppTheme.spacingMd, color: PcHomeColors.border),
        Expanded(
          child: PcScrollBoundary(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: KeyedSubtree(
                key: const Key('pc-home-astronomy-panel'),
                child: astronomyPanel,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _weatherSummaryPanel(PcDashboardLayout layout) => ObservatoryPanel(
    padding: EdgeInsets.all(layout.panelPadding),
    backgroundColor: PcHomeColors.panel,
    borderColor: PcHomeColors.border,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ObservatorySectionHeader(
          title: '날씨 정보',
          icon: Icons.cloud_outlined,
          iconColor: PcHomeColors.muted,
          titleColor: PcHomeColors.text,
          trailing: onWeatherDetail == null
              ? null
              : TextButton(
                  onPressed: onWeatherDetail,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '전체 기상정보 →',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
        ),
        const Divider(height: AppTheme.spacingMd, color: PcHomeColors.border),
        Expanded(
          child: PcScrollBoundary(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: KeyedSubtree(
                key: const Key('pc-home-hourly-weather-panel'),
                child: weatherPanel,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _recommendations(PcDashboardLayout layout) => ObservatoryPanel(
    padding: EdgeInsets.all(layout.panelPadding),
    backgroundColor: PcHomeColors.panel,
    borderColor: PcHomeColors.border,
    child: KeyedSubtree(
      key: const Key('pc-home-recommendations-panel'),
      child: recommendationPanel,
    ),
  );

  Widget _schedule(PcDashboardLayout layout) => ObservatoryPanel(
    padding: EdgeInsets.all(layout.panelPadding),
    backgroundColor: PcHomeColors.panel,
    borderColor: PcHomeColors.border,
    child: KeyedSubtree(
      key: const Key('pc-home-schedule-panel'),
      child: schedulePanel,
    ),
  );

  Widget _summaryColumn(PcDashboardLayout layout) => Column(
    children: [
      Expanded(flex: 11, child: _statusPanel(layout)),
      SizedBox(height: AppTheme.spacingSm + layout.density * 6),
      Expanded(flex: 9, child: _weatherSummaryPanel(layout)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final layout = PcDashboardLayout.maybeOf(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1100) {
          return SizedBox(
            height: rowHeight,
            child: Row(
              key: const Key('pc-home-layout-wide'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 12, child: _summaryColumn(layout)),
                SizedBox(width: layout.panelPadding),
                Expanded(flex: 13, child: _recommendations(layout)),
                SizedBox(width: layout.panelPadding),
                Expanded(flex: 12, child: _schedule(layout)),
              ],
            ),
          );
        }
        return Column(
          key: const Key('pc-home-layout-narrow'),
          children: [
            SizedBox(height: 230, child: _statusPanel(layout)),
            const SizedBox(height: AppTheme.spacingSm),
            SizedBox(height: 205, child: _weatherSummaryPanel(layout)),
            const SizedBox(height: AppTheme.spacingSm),
            SizedBox(height: 315, child: _recommendations(layout)),
            const SizedBox(height: AppTheme.spacingSm),
            SizedBox(height: 300, child: _schedule(layout)),
          ],
        );
      },
    );
  }
}

class _PcHomeHero extends StatelessWidget {
  const _PcHomeHero({required this.siteName, required this.weatherSummary});

  final String siteName;
  final String? weatherSummary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      key: const Key('pc-home-hero'),
      width: double.infinity,
      height:
          constraints.maxWidth >= 720 &&
              (PcDashboardLayout.maybeOf(context)?.viewportHeight ?? 0) < 960
          ? 180
          : 200,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/ui/backgrounds/home_hero_milkyway.png',
            fit: BoxFit.cover,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: AppColors.observatorySidebar),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xF2080E1D),
                  Color(0xB3080E1D),
                  Color(0x33080E1D),
                ],
                stops: [0, 0.48, 1],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth < 720 ? 24 : 44,
              constraints.maxWidth < 720 ? 70 : 28,
              24,
              30,
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: constraints.maxWidth < 720 ? 54 : 68,
                    height: constraints.maxWidth < 720 ? 54 : 68,
                  ),
                ),
                const SizedBox(width: AppTheme.spacingMd),
                Flexible(
                  child: Text(
                    'AstroJournal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (constraints.maxWidth < 720
                                ? Theme.of(context).textTheme.headlineSmall
                                : Theme.of(context).textTheme.headlineLarge)
                            ?.copyWith(
                              color: PcHomeColors.text,
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 22,
            right: constraints.maxWidth < 720 ? 16 : 30,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth < 720
                    ? constraints.maxWidth - 32
                    : 310,
              ),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppTheme.spacingSm,
                runSpacing: AppTheme.spacingXs,
                children: [
                  ObservatoryStatusBadge(
                    label: '관측지 · $siteName',
                    color: PcHomeColors.secondaryAccent,
                  ),
                  ObservatoryStatusBadge(
                    label: weatherSummary ?? '날씨 정보 없음',
                    color: PcHomeColors.text,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PcAstronomyPanel extends StatelessWidget {
  const _PcAstronomyPanel({required this.condition, required this.bortle});

  final ObservationCondition? condition;
  final int? bortle;

  @override
  Widget build(BuildContext context) {
    final value = condition;
    if (value == null) {
      return const _PcEmptyMessage('관측 조건을 준비하고 있습니다.');
    }
    final hasForecast = value.hasTonightForecast;
    final hasStatus =
        hasForecast || value.observationStatus == ObservationStatus.unavailable;
    final statusLabel = hasStatus ? value.observationStatus.headline : '미확인';
    final statusColor = hasForecast
        ? ObservationScoreService.scoreColor(value.score)
        : PcHomeColors.muted;
    final weather = value.weather;
    final density = PcDashboardLayout.maybeOf(context)?.density ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 106 + 34 * density,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: hasForecast
                        ? value.score.clamp(0, 100).toDouble() / 100
                        : 0,
                    strokeWidth: 8 + 2 * density,
                    backgroundColor: PcHomeColors.border,
                    valueColor: AlwaysStoppedAnimation(statusColor),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            statusLabel,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13 + 2 * density,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            hasForecast ? '${value.score}점' : '예보 부족',
                            style: TextStyle(
                              fontSize: 18 + 6 * density,
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacingLg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PcGuideMetric(
                    icon: Icons.cloud_outlined,
                    label: '날씨',
                    value: weather?.description.isNotEmpty == true
                        ? weather!.description
                        : '예보 확인 중',
                  ),
                  _PcGuideMetric(
                    icon: Icons.nightlight_outlined,
                    label: '달빛',
                    value:
                        '${value.moon.illuminationPercent}% · ${value.moon.phaseName}',
                  ),
                  _PcGuideMetric(
                    icon: Icons.auto_awesome_outlined,
                    label: '관측 조건',
                    value: statusLabel,
                  ),
                  if (bortle != null)
                    _PcGuideMetric(
                      icon: Icons.dark_mode_outlined,
                      label: '광해',
                      value: 'Bortle $bortle',
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingMd),
        Text(
          hasStatus
              ? value.statusUserMessage ?? value.summaryText
              : value.weatherError ?? '시간별 예보가 없어 관측지수를 확정할 수 없습니다.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: PcHomeColors.muted,
            fontSize: 12 + 2 * density,
          ),
        ),
      ],
    );
  }
}

class _PcGuideMetric extends StatelessWidget {
  const _PcGuideMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final density = PcDashboardLayout.maybeOf(context)?.density ?? 0;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4 + 2 * density),
      child: Row(
        children: [
          Icon(icon, size: 16 + 3 * density, color: PcHomeColors.muted),
          const SizedBox(width: 7),
          Text(
            '$label  ',
            style: TextStyle(
              color: PcHomeColors.muted,
              fontSize: 11 + 2 * density,
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11 + 2 * density,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PcHourlyWeatherPanel extends StatelessWidget {
  const _PcHourlyWeatherPanel({
    required this.condition,
    required this.isLoading,
  });

  final ObservationCondition? condition;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final slots = condition?.tonightSlots ?? const <TonightObservationSlot>[];
    final density = PcDashboardLayout.maybeOf(context)?.density ?? 0;
    if (slots.isEmpty) {
      return _PcEmptyMessage(
        isLoading ? '시간별 예보를 불러오고 있습니다.' : '시간별 예보가 없습니다.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final visible = slots
                .take(constraints.maxWidth < 260 ? 3 : 5)
                .toList();
            return Column(
              children: [
                Row(
                  children: [
                    for (final slot in visible)
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _formatPcTime(slot.targetTime),
                              style: TextStyle(
                                fontSize: 11 + 2 * density,
                                color: PcHomeColors.muted,
                              ),
                            ),
                            SizedBox(height: 4 + 5 * density),
                            Text(
                              slot.forecast.icon.endsWith('n') &&
                                      slot.forecast.icon.startsWith('01')
                                  ? '☾'
                                  : slot.forecast.weatherEmoji,
                              style: TextStyle(fontSize: 22 + 8 * density),
                            ),
                            SizedBox(height: 3 + 4 * density),
                            Text(
                              '${slot.forecast.temperature.round()}°',
                              style: TextStyle(
                                fontSize: 12 + 3 * density,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '구름 ${slot.forecast.cloudCoverage}%',
                              style: TextStyle(
                                fontSize: 10 + 2 * density,
                                color: PcHomeColors.muted,
                              ),
                            ),
                            Text(
                              '습도 ${slot.forecast.humidity}%',
                              style: TextStyle(
                                fontSize: 10 + 2 * density,
                                color: PcHomeColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PcObservationAssessment extends StatelessWidget {
  const _PcObservationAssessment({required this.condition});

  final ObservationCondition condition;

  @override
  Widget build(BuildContext context) {
    final primaryReason = condition.statusPrimaryReason;
    final infeasibleReason = condition.primaryInfeasibleReason;
    return Container(
      key: const Key('pc-home-observation-assessment'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.background.withAlpha(110),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.textSecondary.withAlpha(35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '관측지수 산정 근거',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          const _PcAssessmentSectionLabel(
            key: Key('pc-home-observation-final-score'),
            label: '최종 관측지수',
          ),
          _PcAssessmentRow(label: '점수', value: '${condition.score}점'),
          const SizedBox(height: 10),
          const _PcAssessmentSectionLabel(
            key: Key('pc-home-observation-verdict'),
            label: '판정',
          ),
          _PcAssessmentRow(
            label: '상태',
            value: _statusLabel(condition.observationStatus),
          ),
          if (primaryReason != null && primaryReason.isNotEmpty)
            _PcAssessmentRow(
              label: condition.observationStatus ==
                      ObservationStatus.unavailable
                  ? '관측 불가 원인'
                  : '주요 판정',
              value: primaryReason,
            ),
          if (infeasibleReason != null &&
              infeasibleReason.isNotEmpty &&
              infeasibleReason != primaryReason)
            _PcAssessmentRow(label: '제약 조건', value: infeasibleReason),
          if (condition.contributions.isNotEmpty ||
              condition.qualityComponents.isNotEmpty) ...[
            const SizedBox(height: 10),
            const _PcAssessmentSectionLabel(
              key: Key('pc-home-observation-score-components'),
              label: '점수 구성',
            ),
            if (condition.contributions.isNotEmpty)
              for (final contribution in condition.contributions)
                _PcAssessmentRow(
                  label: contribution.category,
                  value: '${contribution.points}점',
                  detail: contribution.label.isEmpty
                      ? '★' * contribution.starCount
                      : contribution.label,
                )
            else if (condition.qualityComponents.isNotEmpty)
              for (final component in condition.qualityComponents)
                _PcAssessmentRow(
                  label: component.category,
                  value: '${component.qualityPoints}점',
                  detail: component.starLabel,
                ),
          ],
          const SizedBox(height: 10),
          const _PcAssessmentSectionLabel(
            key: Key('pc-home-observation-forecast-values'),
            label: '실제 예보 조건',
          ),
          if (condition.hasTonightForecast) ...[
            _PcAssessmentRow(
              label: '평균 구름량',
              value: '${condition.averageCloudCoverage.round()}%',
            ),
            _PcAssessmentRow(
              label: '평균 풍속',
              value: '${condition.averageWindSpeed.toStringAsFixed(1)} m/s',
            ),
            _PcAssessmentRow(
              label: '평균 강수확률',
              value: '${condition.averagePrecipitationPop.round()}%',
            ),
            _PcAssessmentRow(
              label: '평균 가시거리',
              value:
                  '${(condition.averageVisibilityMeters / 1000).toStringAsFixed(1)} km',
            ),
          ] else
            const _PcAssessmentRow(label: '예보', value: '미연동 (달만 반영)'),
        ],
      ),
    );
  }

  String _statusLabel(ObservationStatus status) => switch (status) {
    ObservationStatus.good => '관측 가능',
    ObservationStatus.limited => '주의',
    ObservationStatus.unavailable => '관측 불가',
  };
}

class _PcAssessmentSectionLabel extends StatelessWidget {
  const _PcAssessmentSectionLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PcAssessmentRow extends StatelessWidget {
  const _PcAssessmentRow({
    required this.label,
    required this.value,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          if (detail != null) ...[
            Text(
              detail!,
              style: const TextStyle(color: AppColors.solar, fontSize: 12),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PcWeatherTable extends StatefulWidget {
  const _PcWeatherTable({required this.slots, required this.maxBodyHeight});

  final List<TonightObservationSlot> slots;
  final double maxBodyHeight;

  @override
  State<_PcWeatherTable> createState() => _PcWeatherTableState();
}

class _PcWeatherTableState extends State<_PcWeatherTable> {
  final _headerHorizontalController = ScrollController();
  final _bodyHorizontalController = ScrollController();
  final _timeVerticalController = ScrollController();
  final _bodyVerticalController = ScrollController();
  bool _syncingHorizontal = false;
  int? _dragPointer;
  Offset? _dragOrigin;
  Offset? _previousDragPosition;
  bool _draggingBody = false;
  bool _scrollbarsVisible = false;

  static const _rowHeight = 38.0;
  static const _dragThreshold = 6.0;
  static const _labels = [
    '시간',
    '날씨',
    '기온',
    '구름',
    '풍속',
    '습도',
    '강수',
    '가시',
    '결로',
    '지수',
    '별',
  ];
  static const _widths = [
    68.0,
    52.0,
    60.0,
    64.0,
    76.0,
    64.0,
    64.0,
    64.0,
    64.0,
    64.0,
    80.0,
  ];

  @override
  void initState() {
    super.initState();
    _headerHorizontalController.addListener(_syncHeaderToBody);
    _bodyHorizontalController.addListener(_syncBodyToHeader);
    _bodyVerticalController.addListener(_syncBodyToTimeColumn);
  }

  @override
  void dispose() {
    _headerHorizontalController
      ..removeListener(_syncHeaderToBody)
      ..dispose();
    _bodyHorizontalController
      ..removeListener(_syncBodyToHeader)
      ..dispose();
    _timeVerticalController.dispose();
    _bodyVerticalController
      ..removeListener(_syncBodyToTimeColumn)
      ..dispose();
    super.dispose();
  }

  void _syncHeaderToBody() => _syncHorizontal(
    source: _headerHorizontalController,
    target: _bodyHorizontalController,
  );

  void _syncBodyToHeader() => _syncHorizontal(
    source: _bodyHorizontalController,
    target: _headerHorizontalController,
  );

  void _syncHorizontal({
    required ScrollController source,
    required ScrollController target,
  }) {
    if (_syncingHorizontal || !source.hasClients || !target.hasClients) return;
    final targetOffset = source.offset.clamp(
      target.position.minScrollExtent,
      target.position.maxScrollExtent,
    );
    if ((target.offset - targetOffset).abs() < 0.5) return;
    _syncingHorizontal = true;
    target.jumpTo(targetOffset);
    _syncingHorizontal = false;
  }

  void _syncBodyToTimeColumn() {
    if (!_bodyVerticalController.hasClients ||
        !_timeVerticalController.hasClients) {
      return;
    }
    final targetOffset = _bodyVerticalController.offset.clamp(
      _timeVerticalController.position.minScrollExtent,
      _timeVerticalController.position.maxScrollExtent,
    );
    if ((_timeVerticalController.offset - targetOffset).abs() < 0.5) return;
    _timeVerticalController.jumpTo(targetOffset);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      _handleResolvedPointerSignal,
    );
  }

  void _handleResolvedPointerSignal(PointerSignalEvent event) {
    final scrollEvent = event as PointerScrollEvent;
    if (_bodyVerticalController.hasClients) {
      _bodyVerticalController.position.pointerScroll(scrollEvent.scrollDelta.dy);
    }
    scrollEvent.respond(allowPlatformDefault: false);
  }

  void _handleBodyPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryMouseButton) return;
    _dragPointer = event.pointer;
    _dragOrigin = event.position;
    _previousDragPosition = event.position;
  }

  void _handleBodyPointerMove(PointerMoveEvent event) {
    if (event.pointer != _dragPointer ||
        _dragOrigin == null ||
        _previousDragPosition == null) {
      return;
    }
    if (!_draggingBody &&
        (event.position - _dragOrigin!).distance < _dragThreshold) {
      return;
    }
    if (!_draggingBody) {
      setState(() => _draggingBody = true);
    }
    final delta = event.position - _previousDragPosition!;
    _jumpBy(_bodyHorizontalController, delta.dx);
    _jumpBy(_bodyVerticalController, delta.dy);
    _previousDragPosition = event.position;
  }

  void _handleBodyPointerEnd(PointerEvent event) {
    if (event.pointer != _dragPointer) return;
    final wasDragging = _draggingBody;
    _dragPointer = null;
    _dragOrigin = null;
    _previousDragPosition = null;
    _draggingBody = false;
    if (wasDragging) setState(() {});
  }

  void _setScrollbarsVisible(bool visible) {
    if (_scrollbarsVisible == visible) return;
    setState(() => _scrollbarsVisible = visible);
  }

  void _jumpBy(ScrollController controller, double delta) {
    if (!controller.hasClients || delta == 0) return;
    final position = controller.position;
    final targetOffset = (controller.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((controller.offset - targetOffset).abs() < 0.5) return;
    controller.jumpTo(targetOffset);
  }

  @override
  Widget build(BuildContext context) {
    final naturalBodyHeight = widget.slots.length * _rowHeight;
    final bodyHeight = naturalBodyHeight > widget.maxBodyHeight
        ? widget.maxBodyHeight
        : naturalBodyHeight;
    return LayoutBuilder(builder: (context, constraints) {
      final baseWidth = _widths.fold(0.0, (sum, width) => sum + width);
      final remainingBase = baseWidth - _widths.first;
      final extra = constraints.hasBoundedWidth &&
              constraints.maxWidth > baseWidth
          ? constraints.maxWidth - baseWidth : 0.0;
      final widths = <double>[
        _widths.first,
        for (var index = 1; index < _widths.length; index++)
          _widths[index] + extra * _widths[index] / remainingBase,
      ];
      final remainingWidth = widths.skip(1).fold(0.0, (sum, width) => sum + width);
      return Column(
      children: [
        SizedBox(
          key: const Key('pc-home-weather-fixed-header'),
          height: 36,
          child: Row(
            children: [
              _fixedCell(
                widths: widths,
                key: const Key('pc-home-weather-frozen-corner'),
                value: _labels.first,
                header: true,
              ),
              Expanded(
                child: ClipRect(
                  child: SingleChildScrollView(
                    key: const Key('pc-home-weather-horizontal-header'),
                    controller: _headerHorizontalController,
                    scrollDirection: Axis.horizontal,
                    child: _row(
                      _labels.sublist(1),
                      widths: widths,
                      widthOffset: 1,
                      header: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Listener(
          key: const Key('pc-home-weather-wheel-guard'),
          onPointerSignal: _handlePointerSignal,
          child: SizedBox(
            key: const Key('pc-home-weather-scroll-body'),
            height: bodyHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  key: const Key('pc-home-weather-frozen-time-column'),
                  width: widths.first,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: ListView.builder(
                      controller: _timeVerticalController,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: widget.slots.length,
                      itemExtent: _rowHeight,
                      itemBuilder: (context, index) => _fixedCell(
                        widths: widths,
                        value: widget.slots[index].label,
                        alternate: index.isEven,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: MouseRegion(
                    onEnter: (_) => _setScrollbarsVisible(true),
                    onExit: (_) => _setScrollbarsVisible(false),
                    child: Scrollbar(
                      key: const Key('pc-home-weather-horizontal-scrollbar'),
                      controller: _bodyHorizontalController,
                      thumbVisibility: _scrollbarsVisible,
                      interactive: true,
                      thickness: 5,
                      radius: const Radius.circular(3),
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: Scrollbar(
                        key: const Key('pc-home-weather-vertical-scrollbar'),
                        controller: _bodyVerticalController,
                        thumbVisibility: _scrollbarsVisible,
                        interactive: true,
                        thickness: 5,
                        radius: const Radius.circular(3),
                        scrollbarOrientation: ScrollbarOrientation.right,
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.vertical,
                        child: MouseRegion(
                          cursor: _draggingBody
                              ? SystemMouseCursors.grabbing
                              : SystemMouseCursors.grab,
                          child: Listener(
                            key: const Key('pc-home-weather-drag-region'),
                            onPointerDown: _handleBodyPointerDown,
                            onPointerMove: _handleBodyPointerMove,
                            onPointerUp: _handleBodyPointerEnd,
                            onPointerCancel: _handleBodyPointerEnd,
                            child: ClipRect(
                              child: SingleChildScrollView(
                                key: const Key(
                                  'pc-home-weather-horizontal-body',
                                ),
                                controller: _bodyHorizontalController,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: remainingWidth,
                                  height: bodyHeight,
                                  child: ListView.builder(
                                    controller: _bodyVerticalController,
                                    primary: false,
                                    padding: EdgeInsets.zero,
                                    itemCount: widget.slots.length,
                                    itemExtent: _rowHeight,
                                    itemBuilder: (context, index) {
                                      final values = _values(
                                        widget.slots[index],
                                      );
                                      return ColoredBox(
                                        color: index.isEven
                                            ? AppColors.background.withAlpha(70)
                                            : Colors.transparent,
                                        child: _row(
                                          values.sublist(1),
                                          widths: widths,
                                          widthOffset: 1,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    });
  }

  Widget _fixedCell({
    required List<double> widths,
    Key? key,
    required String value,
    bool header = false,
    bool alternate = false,
  }) {
    return Container(
      key: key,
      width: widths.first,
      height: header ? 36 : _rowHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: header
          ? AppColors.surface
          : alternate
          ? AppColors.background.withAlpha(70)
          : Colors.transparent,
      child: Text(
        value,
        style: TextStyle(
          color: header ? AppColors.textSecondary : AppColors.textPrimary,
          fontSize: 12,
          fontWeight: header ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _row(
    List<String> values, {
    required List<double> widths,
    int widthOffset = 0,
    bool header = false,
  }) {
    return Row(
      children: [
        for (var index = 0; index < values.length; index++)
          SizedBox(
            width: widths[index + widthOffset],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                values[index],
                style: TextStyle(
                  color: header
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: header ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }

  List<String> _values(TonightObservationSlot slot) {
    final forecast = slot.forecast;
    final available = slot.canObserve;
    return [
      slot.label,
      forecast.weatherEmoji,
      '${forecast.temperature.round()}℃',
      '${forecast.cloudCoverage}%',
      '${forecast.windSpeed.toStringAsFixed(1)}m/s',
      '${forecast.humidity}%',
      '${forecast.pop.round()}%',
      '${(forecast.visibility / 1000).toStringAsFixed(0)}km',
      slot.condensationRisk.label,
      available ? '${slot.score}' : '불가',
      available ? '★' * slot.starCount : '-',
    ];
  }
}

class _PcRecommendationPanel extends StatefulWidget {
  const _PcRecommendationPanel({required this.home});

  final HomeViewModel home;

  @override
  State<_PcRecommendationPanel> createState() => _PcRecommendationPanelState();
}

class _PcRecommendationPanelState extends State<_PcRecommendationPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.home;
    final items = home.recommendedObjects;
    final layout = PcDashboardLayout.maybeOf(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '추천 촬영 대상',
                style: TextStyle(
                  fontSize: 13 + 3 * layout.density,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            PcScrollEdgeButtons(controller: _scrollController),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: items.isEmpty
                  ? null
                  : () => unawaited(
                      showPcHomeAllRecommendations(
                        context,
                        home.allRecommendedObjects,
                      ),
                    ),
              child: Text(
                '전체 ${home.allRecommendedObjects.length}개 ›',
                style: TextStyle(fontSize: 11 + 2 * layout.density),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingXs),
        if (home.recommendationState !=
            RecommendationComputationState.current) ...[
          HomeRecommendationRefreshNotice(
            state: home.recommendationState,
            message: home.recommendationErrorMessage,
            showingPreviousResults: items.isNotEmpty,
          ),
          const SizedBox(height: AppTheme.spacingSm),
        ],
        if (items.isEmpty)
          Flexible(
            child: PcScrollBoundary(
              child: SingleChildScrollView(
                child: _PcEmptyMessage(
                  home.exclusionReasons.isEmpty
                      ? '추천 가능한 대상이 없습니다.'
                      : home.exclusionReasons.join('\n'),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: PcScrollBoundary(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: ListView.separated(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => SizedBox(height: layout.rowGap),
                  itemBuilder: (context, index) => _PcRecommendationCard(
                    recommendation: items[index],
                    home: home,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PcRecommendationCard extends StatelessWidget {
  const _PcRecommendationCard({
    required this.recommendation,
    required this.home,
  });

  final RecommendationResult recommendation;
  final HomeViewModel home;

  @override
  Widget build(BuildContext context) {
    final object = recommendation.object;
    final layout = PcDashboardLayout.maybeOf(context)!;
    final window = _recommendationWindow(recommendation);
    final altitude = recommendation.observationWindow?.optimalAltitude;
    final detail = [
      if (window != null) '관측 $window',
      if (altitude != null) '고도 ${altitude.round()}°',
    ].join(' · ');
    return SizedBox(
      height: layout.rowHeight,
      child: InkWell(
        onTap: () =>
            unawaited(showPcHomeRecommendationDetail(context, recommendation)),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Container(
          key: Key('pc-home-recommendation-${object.id}'),
          padding: EdgeInsets.symmetric(
            horizontal: 5 + 5 * layout.density,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: PcHomeColors.card,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: PcHomeColors.border),
          ),
          child: Row(
            children: [
              CatalogObjectImage(
                object: object,
                userPhotoPath: home.userPhotoFor(object),
                width: layout.rowImage,
                height: layout.rowImage,
                userPhotoFit: BoxFit.contain,
                assetFit: BoxFit.contain,
                borderRadius: BorderRadius.circular(6),
              ),
              SizedBox(width: 6 + 5 * layout.density),
              Expanded(
                flex: 5,
                child: Text(
                  '${CatalogObjectDisplayFormatter.catalogTitle(object)} · ${object.displayType}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11 + 3 * layout.density,
                  ),
                ),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  flex: 4,
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10 + 2 * layout.density,
                      color: PcHomeColors.muted,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              const ObservatoryStatusBadge(
                label: '추천',
                color: PcHomeColors.secondaryAccent,
              ),
              if (home.canAddToShootingPlan(object.id))
                ShootingPlanActionButton(
                  compact: layout.density < .6,
                  isPlanned: home.isPlanned(object.id),
                  isScheduled: home.isScheduled(object.id),
                  onToggle: () => home.toggleTonightPlan(object.id),
                  backgroundColor:
                      (home.isPlanned(object.id)
                              ? PcHomeColors.muted
                              : PcHomeColors.accent)
                          .withValues(alpha: 0.14),
                  foregroundColor: home.isPlanned(object.id)
                      ? PcHomeColors.muted
                      : PcHomeColors.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PcSchedulePanel extends StatefulWidget {
  const _PcSchedulePanel({required this.home, required this.onDetail});

  final HomeViewModel home;
  final VoidCallback onDetail;

  @override
  State<_PcSchedulePanel> createState() => _PcSchedulePanelState();
}

class _PcSchedulePanelState extends State<_PcSchedulePanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = PcDashboardLayout.maybeOf(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.timeline_outlined,
              size: 17,
              color: PcHomeColors.muted,
            ),
            const SizedBox(width: AppTheme.spacingSm),
            Expanded(
              child: Text(
                '촬영 스케줄',
                style: TextStyle(
                  fontSize: 14 + 2 * layout.density,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            PcScrollEdgeButtons(controller: _scrollController),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: widget.onDetail,
              child: Text(
                '자세히 보기 ›',
                style: TextStyle(fontSize: 11 + 2 * layout.density),
              ),
            ),
          ],
        ),
        if (widget.home.scheduleState != ScheduleComputationState.current) ...[
          HomeScheduleComputationStatus(state: widget.home.scheduleState),
          const SizedBox(height: AppTheme.spacingXs),
        ],
        const SizedBox(height: AppTheme.spacingSm),
        if (widget.home.scheduleItems.isEmpty)
          _PcEmptyMessage(
            widget.home.scheduleEmptyMessage ?? '배정된 촬영 스케줄이 없습니다.',
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return PcScrollBoundary(
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: ListView.separated(
                      controller: _scrollController,
                      physics: const ClampingScrollPhysics(),
                      itemCount: widget.home.scheduleItems.length,
                      separatorBuilder: (_, _) => Divider(
                        height: AppTheme.spacingSm + layout.density * 3,
                        color: PcHomeColors.border,
                      ),
                      itemBuilder: (context, index) => _PcScheduleCard(
                        item: widget.home.scheduleItems[index],
                        home: widget.home,
                        width: constraints.maxWidth - AppTheme.spacingSm,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _PcScheduleCard extends StatelessWidget {
  const _PcScheduleCard({
    required this.item,
    required this.home,
    required this.width,
  });

  final ScheduleItem item;
  final HomeViewModel home;
  final double width;

  @override
  Widget build(BuildContext context) {
    final object = item.catalogObject;
    final layout = PcDashboardLayout.maybeOf(context)!;
    final image = CatalogObjectImage(
      object: object,
      userPhotoPath: home.userPhotoFor(object),
      width: layout.rowImage,
      height: layout.rowImage,
      userPhotoFit: BoxFit.contain,
      assetFit: BoxFit.contain,
      borderRadius: BorderRadius.circular(6),
    );
    final timeLabel =
        '${_formatPcTime(item.startTime)}–${_formatPcTime(item.endTime)}';
    final durationLabel =
        '${item.shootingDuration.inMinutes}분 · ${item.status.label}';
    return Container(
      key: Key('pc-home-schedule-${object.id}'),
      width: width,
      height: layout.rowHeight,
      padding: EdgeInsets.symmetric(
        horizontal: 5 + 5 * layout.density,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: PcHomeColors.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: PcHomeColors.border),
      ),
      child: Row(
        children: [
          image,
          SizedBox(width: 6 + 5 * layout.density),
          Expanded(
            flex: 5,
            child: Text(
              '${CatalogObjectDisplayFormatter.catalogTitle(object)} · ${object.displayType}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11 + 3 * layout.density,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: Text(
              durationLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10 + 2 * layout.density,
                color: PcHomeColors.muted,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            timeLabel,
            maxLines: 1,
            style: TextStyle(
              color: PcHomeColors.secondaryAccent,
              fontSize: 10 + 2 * layout.density,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PcEmptyMessage extends StatelessWidget {
  const _PcEmptyMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingLg),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _PcHomeFailure extends StatelessWidget {
  const _PcHomeFailure({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: AppTheme.spacingSm),
          OutlinedButton.icon(
            onPressed: () => unawaited(onRetry()),
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

String _formatPcTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String? _recommendationWindow(RecommendationResult result) {
  final window = result.observationWindow;
  if (window == null) return null;
  final summary = window.feasibleWindowSummary;
  if (summary != null) return summary;
  final start = window.optimalStartTime ?? window.recommendStartTime;
  final end = window.optimalEndTime ?? window.observationEndTime;
  if (start == null || end == null) return null;
  return '${_formatPcTime(start)} ~ ${_formatPcTime(end)}';
}
