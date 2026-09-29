import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/formatters/catalog_object_display_formatter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/observation_status.dart';
import '../../../data/models/recommendation_result.dart';
import '../../../data/models/scheduler_models.dart';
import '../../../services/observation_score_service.dart';
import '../../../shared/widgets/catalog_equipment_chips_row.dart';
import '../../../shared/widgets/catalog_object_image.dart';
import '../../observation_site/view/observation_site_detail_screen.dart';
import '../../settings/view/observation_site_edit_screen.dart';
import '../../settings/view/observation_site_list_screen.dart';
import '../viewmodel/astronomy_events_view_model.dart';
import '../viewmodel/home_view_model.dart';
import 'home_screen.dart';
import 'widgets/astronomy_events_section.dart';
import 'widgets/home_observation_context_controls.dart';
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

  @override
  Widget build(BuildContext context) {
    final home = context.read<HomeViewModel>();
    return Scaffold(
      backgroundColor: AppColors.background,
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
    );
  }

  Widget _buildDashboard(HomeViewModel home) {
    final condition = home.observationCondition;
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
      schedulePanel: _PcSchedulePanel(home: home),
      eventsFooter: const AstronomyEventsSection(),
    );
  }
}

/// Presentation-only frame used by the Windows home dashboard.
///
/// Keeping the responsive frame independent from [HomeViewModel] makes its
/// overflow contract testable without duplicating any astronomy calculation.
class PcHomeDashboardView extends StatelessWidget {
  const PcHomeDashboardView({
    super.key,
    required this.contextControls,
    required this.astronomyPanel,
    required this.hourlyWeatherPanel,
    required this.recommendationPanel,
    required this.schedulePanel,
    required this.eventsFooter,
    this.onRefresh,
  });

  final Widget contextControls;
  final Widget astronomyPanel;
  final Widget hourlyWeatherPanel;
  final Widget recommendationPanel;
  final Widget schedulePanel;
  final Widget eventsFooter;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          key: const Key('pc-home-sticky-header'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingLg,
            AppTheme.spacingMd,
            AppTheme.spacingLg,
            AppTheme.spacingMd,
          ),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border(
              bottom: BorderSide(color: AppColors.ic.withAlpha(35)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '오늘 밤 촬영 도우미',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onRefresh != null)
                    IconButton(
                      key: const Key('pc-home-refresh'),
                      tooltip: '홈 새로고침',
                      onPressed: () => unawaited(onRefresh!()),
                      icon: const Icon(Icons.refresh_outlined),
                    ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingSm),
              KeyedSubtree(
                key: const Key('pc-home-context-controls'),
                child: contextControls,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: const Key('pc-home-scroll-view'),
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PcHomeResponsiveColumns(
                  left: Column(
                    children: [
                      KeyedSubtree(
                        key: const Key('pc-home-astronomy-panel'),
                        child: astronomyPanel,
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                      KeyedSubtree(
                        key: const Key('pc-home-hourly-weather-panel'),
                        child: hourlyWeatherPanel,
                      ),
                    ],
                  ),
                  middle: KeyedSubtree(
                    key: const Key('pc-home-recommendations-panel'),
                    child: recommendationPanel,
                  ),
                  right: KeyedSubtree(
                    key: const Key('pc-home-schedule-panel'),
                    child: schedulePanel,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingLg),
                Container(
                  key: const Key('pc-home-astronomy-events'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    border: Border.all(color: AppColors.ic.withAlpha(45)),
                  ),
                  child: eventsFooter,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PcHomeResponsiveColumns extends StatelessWidget {
  const _PcHomeResponsiveColumns({
    required this.left,
    required this.middle,
    required this.right,
  });

  final Widget left;
  final Widget middle;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1180) {
          return Row(
            key: const Key('pc-home-layout-wide'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: left),
              const SizedBox(width: AppTheme.spacingMd),
              Expanded(flex: 4, child: middle),
              const SizedBox(width: AppTheme.spacingMd),
              Expanded(flex: 4, child: right),
            ],
          );
        }
        if (constraints.maxWidth >= 760) {
          return Column(
            key: const Key('pc-home-layout-medium'),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: left),
                  const SizedBox(width: AppTheme.spacingMd),
                  Expanded(flex: 4, child: middle),
                ],
              ),
              const SizedBox(height: AppTheme.spacingMd),
              right,
            ],
          );
        }
        return Column(
          key: const Key('pc-home-layout-narrow'),
          children: [
            left,
            const SizedBox(height: AppTheme.spacingMd),
            middle,
            const SizedBox(height: AppTheme.spacingMd),
            right,
          ],
        );
      },
    );
  }
}

class _PcAstronomyPanel extends StatelessWidget {
  const _PcAstronomyPanel({required this.condition, required this.bortle});

  final ObservationCondition? condition;
  final int? bortle;

  @override
  Widget build(BuildContext context) {
    final value = condition;
    if (value == null) {
      return const _PcPanel(
        icon: Icons.nightlight_outlined,
        title: '천문정보',
        child: _PcEmptyMessage('천문정보를 준비하고 있습니다.'),
      );
    }
    final weather = value.weather;
    return _PcPanel(
      icon: Icons.nightlight_outlined,
      title: '천문정보',
      trailing: _ScoreBadge(score: value.score),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.commentText,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          _PcObservationAssessment(condition: value),
          const SizedBox(height: AppTheme.spacingMd),
          Wrap(
            spacing: AppTheme.spacingSm,
            runSpacing: AppTheme.spacingSm,
            children: [
              _PcInfoValue(label: '관측지', value: value.siteName),
              _PcInfoValue(
                label: '달',
                value:
                    '${value.moon.phaseEmoji} ${value.moon.phaseName} · ${value.moon.illuminationPercent}%',
              ),
              _PcInfoValue(
                label: '월령',
                value: '${value.moon.age.toStringAsFixed(1)}일',
              ),
              if (bortle != null)
                _PcInfoValue(label: '광해', value: 'Bortle $bortle'),
              if (weather != null) ...[
                _PcInfoValue(
                  label: '일출',
                  value: _formatPcTime(weather.sunrise),
                ),
                _PcInfoValue(label: '일몰', value: _formatPcTime(weather.sunset)),
                _PcInfoValue(
                  label: '천문박명 시작',
                  value: _formatPcTime(
                    weather.sunrise.subtract(const Duration(minutes: 80)),
                  ),
                ),
                _PcInfoValue(
                  label: '천문박명 종료',
                  value: _formatPcTime(
                    weather.sunset.add(const Duration(minutes: 80)),
                  ),
                ),
              ],
              if (value.recommendedWindow.isNotEmpty)
                _PcInfoValue(
                  label: '추천 관측시간',
                  value: value.recommendedWindow,
                  wide: true,
                ),
            ],
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
    return _PcPanel(
      icon: Icons.cloud_outlined,
      title: '시간대별 기상정보',
      trailing: isLoading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      child: slots.isEmpty
          ? _PcEmptyMessage(isLoading ? '예보를 불러오고 있습니다.' : '시간대별 예보가 없습니다.')
          : _PcWeatherTable(slots: slots),
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
      padding: const EdgeInsets.all(AppTheme.spacingSm),
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
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const _PcAssessmentSectionLabel(
            key: Key('pc-home-observation-final-score'),
            label: '최종 관측지수',
          ),
          _PcAssessmentRow(label: '점수', value: '${condition.score}점'),
          const SizedBox(height: 6),
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
            const SizedBox(height: 6),
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
          const SizedBox(height: 6),
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
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          if (detail != null) ...[
            Text(
              detail!,
              style: const TextStyle(color: AppColors.solar, fontSize: 10),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
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
  const _PcWeatherTable({required this.slots});

  final List<TonightObservationSlot> slots;

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
  static const _maxBodyHeight = 304.0;
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
    final bodyHeight = naturalBodyHeight > _maxBodyHeight
        ? _maxBodyHeight
        : naturalBodyHeight;
    return Column(
      children: [
        SizedBox(
          key: const Key('pc-home-weather-fixed-header'),
          height: 36,
          child: Row(
            children: [
              _fixedCell(
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
                  width: _widths.first,
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
                                  width: _remainingColumnsWidth,
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
  }

  double get _remainingColumnsWidth =>
      _widths.skip(1).fold(0.0, (sum, width) => sum + width);

  Widget _fixedCell({
    Key? key,
    required String value,
    bool header = false,
    bool alternate = false,
  }) {
    return Container(
      key: key,
      width: _widths.first,
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
          fontSize: 11,
          fontWeight: header ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _row(
    List<String> values, {
    int widthOffset = 0,
    bool header = false,
  }) {
    return Row(
      children: [
        for (var index = 0; index < values.length; index++)
          SizedBox(
            width: _widths[index + widthOffset],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                values[index],
                style: TextStyle(
                  color: header
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontSize: 11,
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

class _PcRecommendationPanel extends StatelessWidget {
  const _PcRecommendationPanel({required this.home});

  final HomeViewModel home;

  @override
  Widget build(BuildContext context) {
    final items = home.recommendedObjects.take(4).toList(growable: false);
    return _PcPanel(
      icon: Icons.auto_awesome,
      title: '오늘 밤 추천 대상',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            _PcEmptyMessage(
              home.exclusionReasons.isEmpty
                  ? '추천 가능한 대상이 없습니다.'
                  : home.exclusionReasons.join('\n'),
            )
          else
            for (var index = 0; index < items.length; index++) ...[
              _PcRecommendationCard(
                rank: index + 1,
                recommendation: items[index],
                home: home,
              ),
              if (index < items.length - 1)
                const SizedBox(height: AppTheme.spacingSm),
            ],
        ],
      ),
    );
  }
}

class _PcRecommendationCard extends StatelessWidget {
  const _PcRecommendationCard({
    required this.rank,
    required this.recommendation,
    required this.home,
  });

  final int rank;
  final RecommendationResult recommendation;
  final HomeViewModel home;

  @override
  Widget build(BuildContext context) {
    final object = recommendation.object;
    final accent = object.catalog.accentColor;
    final chips = home.todayEquipmentChipsFor(object.id);
    final window = _recommendationWindow(recommendation);
    return Container(
      key: Key('pc-home-recommendation-${object.id}'),
      padding: const EdgeInsets.all(AppTheme.spacingSm),
      decoration: BoxDecoration(
        color: accent.withAlpha(18),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: accent.withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CatalogObjectImage(
            object: object,
            userPhotoPath: home.userPhotoFor(object),
            width: 62,
            height: 62,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$rank. ${CatalogObjectDisplayFormatter.catalogTitle(object)}',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
                if (CatalogObjectDisplayFormatter.subtitleText(
                  object,
                ).isNotEmpty)
                  Text(
                    CatalogObjectDisplayFormatter.subtitleText(object),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${'★' * recommendation.starCount} · ${recommendation.score.round()}점 · ${recommendation.reason}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                if (window != null)
                  Text(
                    window,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                if (!chips.isEmpty) ...[
                  const SizedBox(height: 4),
                  CatalogEquipmentChipsRow(chips: chips),
                ],
                if (home.canAddToShootingPlan(object.id)) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ShootingPlanActionButton(
                      compact: true,
                      isPlanned: home.isPlanned(object.id),
                      isScheduled: home.isScheduled(object.id),
                      onToggle: () => home.toggleTonightPlan(object.id),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PcSchedulePanel extends StatelessWidget {
  const _PcSchedulePanel({required this.home});

  final HomeViewModel home;

  @override
  Widget build(BuildContext context) {
    return _PcPanel(
      icon: Icons.timeline_outlined,
      title: '촬영 스케줄',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeScheduleComputationStatus(state: home.scheduleState),
          const SizedBox(height: AppTheme.spacingSm),
          if (home.scheduleItems.isEmpty)
            _PcEmptyMessage(home.scheduleEmptyMessage ?? '배정된 촬영 스케줄이 없습니다.')
          else
            for (var index = 0; index < home.scheduleItems.length; index++) ...[
              _PcScheduleCard(item: home.scheduleItems[index], home: home),
              if (index < home.scheduleItems.length - 1)
                const SizedBox(height: AppTheme.spacingSm),
            ],
        ],
      ),
    );
  }
}

class _PcScheduleCard extends StatelessWidget {
  const _PcScheduleCard({required this.item, required this.home});

  final ScheduleItem item;
  final HomeViewModel home;

  @override
  Widget build(BuildContext context) {
    final object = item.catalogObject;
    final accent = object.catalog.accentColor;
    final flags = <String>[
      item.status.label,
      if (item.isManual) '수기 등록',
      if (item.hasTimeOverride) '시간 고정',
      if (item.framingWindow != null) '같은 구도',
    ];
    return Container(
      key: Key('pc-home-schedule-${object.id}'),
      padding: const EdgeInsets.all(AppTheme.spacingSm),
      decoration: BoxDecoration(
        color: accent.withAlpha(18),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: accent.withAlpha(70)),
      ),
      child: Row(
        children: [
          CatalogObjectImage(
            object: object,
            userPhotoPath: home.userPhotoFor(object),
            width: 54,
            height: 54,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(width: AppTheme.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_formatPcTime(item.startTime)} ~ ${_formatPcTime(item.endTime)}',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
                Text(
                  CatalogObjectDisplayFormatter.catalogTitle(object),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${item.durationLabel} · ${flags.join(' · ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PcPanel extends StatelessWidget {
  const _PcPanel({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.ic.withAlpha(45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.ic),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),
          child,
        ],
      ),
    );
  }
}

class _PcInfoValue extends StatelessWidget {
  const _PcInfoValue({
    required this.label,
    required this.value,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? 250 : 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final color = ObservationScoreService.scoreColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$score점',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
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
