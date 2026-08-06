import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/formatters/catalog_object_display_formatter.dart';
import '../../../core/navigation/app_navigation_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/catalog_equipment_chips.dart';
import '../../../data/models/object_observation_window.dart';
import '../../../data/models/observation_context.dart';
import '../../../data/models/observation_score_contribution.dart';
import '../../../data/models/observation_status.dart';
import '../../../data/models/recommendation_result.dart';
import '../../../data/models/scheduler_models.dart';
import '../../../data/models/observation_quality_component.dart';
import '../../../services/exposure_policy.dart';
import '../../../services/object_imaging_profile_provider.dart';
import '../../../services/observation_score_service.dart';
import '../../../shared/widgets/catalog_equipment_chips_row.dart';
import '../../../shared/widgets/equipment_recommendation_section.dart';
import '../../../shared/widgets/sky_map_location_button.dart';
import '../view/widgets/equipment_recommendation_carousel.dart';
import '../view/widgets/shooting_plan_action_button.dart';
import '../../../core/constants/astro_season.dart';
import '../../../services/season_planner_service.dart';
import '../../catalog/viewmodel/catalog_view_model.dart';
import '../../season/view/season_planner_screen.dart';
import '../../settings/view/settings_screen.dart';
import '../viewmodel/home_view_model.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

String _catalogLabel(CatalogType type) {
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
    case CatalogType.barnard:
      return 'Barnard';
    case CatalogType.ldn:
      return 'LDN';
    case CatalogType.lbn:
      return 'LBN';
    case CatalogType.star:
      return 'Stars';
    case CatalogType.solar:
      return 'Solar System';
    case CatalogType.milky:
      return 'Milky Way';
  }
}

Color _scoreColor(int score) => ObservationScoreService.scoreColor(score);

String _formatTime(DateTime dt) {
  final l = dt.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String _formatDateTime(DateTime dt) {
  final l = dt.toLocal();
  return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String? _resolveExposureTimeLineLabel(
  BuildContext context,
  HomeViewModel homeVm,
  RecommendationResult recommended,
) {
  final ObservationContext? sessionContext = homeVm.lastSessionContext;
  if (sessionContext == null) return null;

  final policy = context.read<ExposurePolicy>();
  final profileProvider = context.read<ObjectImagingProfileProvider>();
  final profile = profileProvider.profileFor(recommended.object);

  final minimum = policy.calculateMinimumExposure(
    bortle: sessionContext.bortle,
    brightness: sessionContext.brightness,
    profile: profile,
  );
  final recommendedExposure = policy.calculateRecommendedExposure(
    bortle: sessionContext.bortle,
    brightness: sessionContext.brightness,
    profile: profile,
  );

  return '${minimum.inMinutes}분 / ${recommendedExposure.inMinutes}분';
}

// ── HomeScreen ───────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<HomeViewModel, ({bool loading, String? error})>(
      selector: (_, vm) => (loading: vm.isLoading, error: vm.errorMessage),
      builder: (context, state, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('천체 촬영 도우미'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '관리자',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
          body: state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.error != null
                  ? Center(child: Text(state.error!))
                  // deferred 로드 후 진척률·추천이 채워져도 Selector는 갱신되지
                  // 않으므로, 본문만 VM listenable로 다시 그린다.
                  : ListenableBuilder(
                      listenable: context.read<HomeViewModel>(),
                      builder: (context, _) => _HomeBody(
                        viewModel: context.read<HomeViewModel>(),
                      ),
                    ),
        );
      },
    );
  }
}

// ── _HomeBody ────────────────────────────────────────────────────────────────

enum _RecommendationSectionTab { targets, equipment }

class _HomeBody extends StatefulWidget {
  const _HomeBody({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  _RecommendationSectionTab _recommendationTab =
      _RecommendationSectionTab.targets;
  int _equipmentGroupIndex = 0;

  HomeViewModel get viewModel => widget.viewModel;

  String _seasonText(int month) {
    if (month >= 3 && month <= 5) return '봄 하늘';
    if (month >= 6 && month <= 8) return '여름 하늘';
    if (month >= 9 && month <= 11) return '가을 하늘';
    return '겨울 하늘';
  }

  void _showObservationDetail(BuildContext context) {
    final condition = viewModel.observationCondition;
    if (condition == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ObservationDetailSheet(condition: condition),
    );
  }

  void _showObjectDetail(BuildContext context, RecommendationResult rec) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RecommendDetailSheet(recommended: rec),
    );
  }

  void _showShootingOrderEditor(BuildContext context, HomeViewModel homeVm) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _ShootingOrderEditSheet(viewModel: homeVm),
    );
  }

  void _showAllRecommended(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RecommendedListSheet(
        items: viewModel.allRecommendedObjects,
        month: DateTime.now().month,
      ),
    );
  }

  void _showEquipmentRecommended(BuildContext context) {
    final groups = viewModel.equipmentTonightGroups;
    if (groups.isEmpty) return;
    final index = _equipmentGroupIndex.clamp(0, groups.length - 1);
    final group = groups[index];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RecommendedListSheet(
        items: group.targets,
        month: DateTime.now().month,
        title: '${group.equipment.name} 추천 대상',
        canAddToPlan: group.isVisual
            ? (_) => false
            : viewModel.canAddToShootingPlan,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final condition = viewModel.observationCondition;
    final isUnavailable =
        condition?.observationStatus == ObservationStatus.unavailable;
    final equipmentGroups = viewModel.equipmentTonightGroups;
    final equipmentIndex = equipmentGroups.isEmpty
        ? 0
        : _equipmentGroupIndex.clamp(0, equipmentGroups.length - 1);
    final selectedEquipmentGroup =
        equipmentGroups.isEmpty ? null : equipmentGroups[equipmentIndex];

    // Expanded+비스크롤 Grid 때문에 휴대폰에서 상하 드래그가 막히던 구조.
    // 본문 전체를 스크롤하고, 카테고리 그리드는 shrinkWrap으로 넣는다.
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (condition != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingLg,
                AppTheme.spacingSm,
                AppTheme.spacingLg,
                0,
              ),
              child: _ObservationIndexCard(
                condition: condition,
                isWeatherLoading: viewModel.isWeatherLoading,
                onDetailTap: () => _showObservationDetail(context),
                onRefresh: () => context.read<HomeViewModel>().refresh(),
              ),
            ),
          if (condition != null) const SizedBox(height: AppTheme.spacingSm),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingLg,
            ),
            child: _SeasonPlannerEntryCard(month: now.month),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '오늘의 추천',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        if (_recommendationTab ==
                            _RecommendationSectionTab.targets)
                          Text(
                            _seasonText(now.month),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    if ((_recommendationTab ==
                            _RecommendationSectionTab.targets &&
                        viewModel.allRecommendedObjects.isNotEmpty) ||
                        (_recommendationTab ==
                                _RecommendationSectionTab.equipment &&
                            selectedEquipmentGroup != null &&
                            selectedEquipmentGroup.targets.isNotEmpty))
                      TextButton(
                        onPressed: () {
                          if (_recommendationTab ==
                              _RecommendationSectionTab.targets) {
                            _showAllRecommended(context);
                          } else {
                            _showEquipmentRecommended(context);
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child:
                            const Text('더보기', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingSm),
                SegmentedButton<_RecommendationSectionTab>(
                  segments: const [
                    ButtonSegment(
                      value: _RecommendationSectionTab.targets,
                      label: Text('추천 대상', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: _RecommendationSectionTab.equipment,
                      label: Text('추천 장비', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {_recommendationTab},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _recommendationTab = selection.first;
                      if (selection.first ==
                          _RecommendationSectionTab.equipment) {
                        _equipmentGroupIndex = 0;
                      }
                    });
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          if (isUnavailable && condition != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLg,
              ),
              child: _ObservationUnavailableNotice(condition: condition),
            ),
          if (isUnavailable && condition != null)
            const SizedBox(height: AppTheme.spacingSm),
          if (viewModel.observationCondition?.observationStatus ==
              ObservationStatus.limited)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLg,
              ),
              child: _LimitedRecommendationNotice(
                message: viewModel
                        .observationCondition?.limitedRecommendationNotice ??
                    ObservationStatus.limited.limitedRecommendationNotice,
              ),
            ),
          if (viewModel.observationCondition?.observationStatus ==
              ObservationStatus.limited)
            const SizedBox(height: AppTheme.spacingSm),
          if (_recommendationTab == _RecommendationSectionTab.targets)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLg,
              ),
              child: viewModel.recommendedObjects.isEmpty
                  ? _NoRecommendationWidget(
                      reasons: viewModel.exclusionReasons,
                    )
                  : _RecommendedObjectGrid(
                      items: viewModel.recommendedObjects.take(4).toList(),
                      onTap: (rec) => _showObjectDetail(context, rec),
                      isPlanned: viewModel.isPlanned,
                      equipmentChipsFor: viewModel.todayEquipmentChipsFor,
                      canAddToPlan: viewModel.canAddToShootingPlan,
                      onTogglePlan: (id) =>
                          context.read<HomeViewModel>().toggleTonightPlan(id),
                    ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EquipmentRecommendationCarousel(
                    groups: equipmentGroups,
                    initialIndex: equipmentIndex,
                    onIndexChanged: (index) {
                      setState(() => _equipmentGroupIndex = index);
                    },
                  ),
                  if (selectedEquipmentGroup != null &&
                      selectedEquipmentGroup.targets.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.spacingSm),
                    _RecommendedObjectGrid(
                      items: selectedEquipmentGroup.targets.take(4).toList(),
                      onTap: (rec) => _showObjectDetail(context, rec),
                      isPlanned: viewModel.isPlanned,
                      equipmentChipsFor: viewModel.todayEquipmentChipsFor,
                      canAddToPlan: (id) =>
                          !selectedEquipmentGroup.isVisual &&
                          viewModel.canAddToShootingPlan(id),
                      onTogglePlan: (id) => context
                          .read<HomeViewModel>()
                          .toggleTonightPlan(id),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: AppTheme.spacingMd),
          if (viewModel.scheduleItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLg,
              ),
              child: _ObservationSessionTimeline(
                items: viewModel.scheduleItems,
                onTap: (rec) => _showObjectDetail(context, rec),
                onEdit: () => _showShootingOrderEditor(context, viewModel),
              ),
            )
          else if (viewModel.scheduleEmptyMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLg,
              ),
              child: _ScheduleEmptyWidget(
                message: viewModel.scheduleEmptyMessage!,
              ),
            ),
          if (viewModel.scheduleItems.isNotEmpty ||
              viewModel.scheduleEmptyMessage != null)
            const SizedBox(height: AppTheme.spacingMd),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingLg,
            ),
            child: Text(
              '카테고리별 진행 현황',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingLg,
              0,
              AppTheme.spacingLg,
              AppTheme.spacingMd,
            ),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppTheme.spacingSm,
                mainAxisSpacing: AppTheme.spacingSm,
                mainAxisExtent: 110,
              ),
              itemCount: viewModel.categoryProgress.length,
              itemBuilder: (context, index) {
                return _CategoryProgressCard(
                  progress: viewModel.categoryProgress[index],
                  compact: false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── 계절별 촬영 대상 진입 카드 ───────────────────────────────────────────────

class _SeasonPlannerEntryCard extends StatelessWidget {
  const _SeasonPlannerEntryCard({required this.month});

  final int month;

  @override
  Widget build(BuildContext context) {
    const service = SeasonPlannerService();
    final season = AstroSeason.fromMonth(month);
    // CatalogViewModel 전체 watch 대신 revision만 구독해 홈 불필요 리빌드를 줄인다.
    return Selector<CatalogViewModel, int>(
      selector: (_, vm) => vm.objectsRevision,
      builder: (context, revision, child) {
        final objects = context.read<CatalogViewModel>().allObjects;
        final summary = service.summarize(
          objects: objects,
          month: month,
          season: season,
        );
        return _buildCard(context, season, summary);
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    AstroSeason season,
    SeasonSummary summary,
  ) {

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: () => SeasonPlannerScreen.open(context),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.solar.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  color: AppColors.solar,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppTheme.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${season.label} 하늘 · 계절별 촬영 대상',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '추천 ${summary.total}개 · 미촬영 ${summary.uncaptured}개',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ① 관측지수 카드 ──────────────────────────────────────────────────────────

class _ObservationIndexCard extends StatelessWidget {
  const _ObservationIndexCard({
    required this.condition,
    required this.isWeatherLoading,
    required this.onDetailTap,
    required this.onRefresh,
  });

  final ObservationCondition condition;
  final bool isWeatherLoading;
  final VoidCallback onDetailTap;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scoreCol = condition.isObservationFeasible
        ? _scoreColor(condition.score)
        : const Color(0xFFEF4444);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingSm,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surface,
            const Color(0xFF0A1628),
          ],
        ),
        border: Border.all(
          color: scoreCol.withAlpha(100),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 12,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  condition.siteName,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isWeatherLoading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else ...[
                if (condition.isWeatherFromCache)
                  Tooltip(
                    message: condition.weatherCachedAt != null
                        ? '오프라인 · ${_formatDateTime(condition.weatherCachedAt!)} 저장'
                        : '오프라인 · 저장된 날씨 정보',
                    child: const Icon(
                      Icons.offline_bolt_outlined,
                      size: 13,
                      color: AppColors.solar,
                    ),
                  ),
                if (condition.weatherError != null && !condition.hasWeather)
                  Tooltip(
                    message: condition.weatherError!,
                    child: const Icon(
                      Icons.cloud_off_outlined,
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                GestureDetector(
                  onTap: onRefresh,
                  child: const Icon(
                    Icons.refresh_outlined,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (condition.isObservationFeasible) ...[
                Text(
                  '${condition.score}',
                  style: TextStyle(
                    color: scoreCol,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '/ 100',
                    style: TextStyle(
                      color: scoreCol.withAlpha(160),
                      fontSize: 12,
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  '관측 불가',
                  style: TextStyle(
                    color: scoreCol,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ],
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '관측지수',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9,
                    ),
                  ),
                  if (condition.isObservationFeasible)
                    _StarsRow(count: condition.starCount),
                ],
              ),
            ],
          ),
          if (condition.isObservationFeasible) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: condition.score / 100,
                minHeight: 3,
                backgroundColor: scoreCol.withAlpha(38),
                valueColor: AlwaysStoppedAnimation<Color>(scoreCol),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            condition.commentText,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (condition.observationWindow != null) ...[
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 11, height: 1.2),
                children: [
                  const TextSpan(
                    text: '추천 ',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  TextSpan(
                    text: condition.observationWindow!.label,
                    style: TextStyle(
                      color: _scoreColor(condition.windowAverageScore),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const TextSpan(
                    text: ' · ',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  TextSpan(
                    text: '${condition.windowAverageScore}점',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _MetricsRow(condition: condition)),
              OutlinedButton.icon(
                onPressed: onDetailTap,
                icon: const Icon(Icons.expand_more, size: 14),
                label: const Text('상세'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: BorderSide(
                    color: AppColors.textSecondary.withAlpha(80),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSm,
                    vertical: 2,
                  ),
                  textStyle: const TextStyle(fontSize: 11),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StarsRow extends StatelessWidget {
  const _StarsRow({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < count ? Icons.star_rounded : Icons.star_outline_rounded,
          color: AppColors.solar,
          size: 14,
        ),
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.condition});
  final ObservationCondition condition;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTheme.spacingSm,
      runSpacing: 2,
      children: [
        if (condition.hasTonightForecast) ...[
          _MetricChip(
            icon: Icons.thermostat_outlined,
            label: '${condition.averageTemperature.toStringAsFixed(1)}°C',
          ),
          _MetricChip(
            icon: Icons.cloud_outlined,
            label: '☁ ${condition.averageCloudCoverage.round()}%',
          ),
          _MetricChip(
            icon: Icons.air,
            label: '${condition.averageWindSpeed.toStringAsFixed(1)}m/s',
          ),
        ] else if (condition.hasWeather) ...[
          _MetricChip(
            icon: Icons.thermostat_outlined,
            label: '${condition.weather!.temperature.toStringAsFixed(1)}°C',
          ),
          _MetricChip(
            icon: Icons.cloud_outlined,
            label: '☁ ${condition.weather!.cloudCoverage}%',
          ),
          _MetricChip(
            icon: Icons.air,
            label: '${condition.weather!.windSpeed.toStringAsFixed(1)}m/s',
          ),
        ] else
          _MetricChip(
            icon: Icons.cloud_off_outlined,
            label: '날씨 미연동',
          ),
        _MetricChip(
          icon: null,
          emoji: condition.moon.phaseEmoji,
          label: '월령 ${condition.moon.age.toStringAsFixed(1)}일',
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    this.icon,
    this.emoji,
    required this.label,
  }) : assert(icon != null || emoji != null);

  final IconData? icon;
  final String? emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: 12, color: AppColors.textSecondary)
        else
          Text(emoji!, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ── 관측지수 상세 시트 ──────────────────────────────────────────────────────

class _ObservationDetailSheet extends StatelessWidget {
  const _ObservationDetailSheet({required this.condition});
  final ObservationCondition condition;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final w = condition.weather;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacingXl,
          AppTheme.spacingLg,
          AppTheme.spacingXl,
          32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withAlpha(102),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingLg),
            Row(
              children: [
                Text(
                  condition.isObservationFeasible
                      ? '${condition.score}점'
                      : '관측 불가',
                  style: TextStyle(
                    color: condition.isObservationFeasible
                        ? _scoreColor(condition.score)
                        : const Color(0xFFEF4444),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: AppTheme.spacingMd),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (condition.isObservationFeasible)
                      _StarsRow(count: condition.starCount),
                    if (condition.isObservationFeasible)
                      const SizedBox(height: 2),
                    Text(
                      condition.commentText,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingLg),

            if (condition.tonightSlots.isNotEmpty) ...[
              _SheetSection(
                icon: Icons.nights_stay_outlined,
                iconColor: AppColors.ic,
                title: '오늘 밤 관측정보',
                child: _TonightObservationMatrix(
                  slots: condition.tonightSlots,
                  bestSlot: condition.bestTonightSlot,
                  observationWindow: condition.observationWindow,
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ],

            // 현재 날씨 (참고)
            if (w != null) ...[
              _SheetSection(
                icon: Icons.wb_sunny_outlined,
                iconColor: AppColors.solar,
                title: '현재 날씨 (참고)',
                child: Column(
                  children: [
                    _InfoRow(
                      label: '기온',
                      value:
                          '${w.temperature.toStringAsFixed(1)}°C',
                    ),
                    _InfoRow(
                      label: '체감온도',
                      value: '${w.feelsLike.toStringAsFixed(1)}°C',
                    ),
                    _InfoRow(label: '습도', value: '${w.humidity}%'),
                    _InfoRow(
                      label: '풍속',
                      value:
                          '${w.windSpeed.toStringAsFixed(1)} m/s',
                    ),
                    _InfoRow(
                      label: '풍향',
                      value: '${w.windDirectionLabel} (${w.windDegree}°)',
                    ),
                    _InfoRow(label: '기압', value: '${w.pressure} hPa'),
                    _InfoRow(label: '구름량', value: '${w.cloudCoverage}%'),
                    _InfoRow(
                      label: '가시거리',
                      value:
                          '${(w.visibility / 1000).toStringAsFixed(1)} km',
                    ),
                    if (w.description.isNotEmpty)
                      _InfoRow(label: '날씨', value: w.description),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ],

            // 달 정보
            _SheetSection(
              icon: Icons.nightlight_round,
              iconColor: AppColors.milky,
              title: '달 정보',
              child: Column(
                children: [
                  _InfoRow(
                    label: '월령',
                    value:
                        '${condition.moon.age.toStringAsFixed(1)}일',
                  ),
                  _InfoRow(
                    label: '달 위상',
                    value:
                        '${condition.moon.phaseEmoji} ${condition.moon.phaseName}',
                  ),
                  _InfoRow(
                    label: '달 밝기',
                    value: '${condition.moon.illuminationPercent}%',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // 천문 정보
            if (w != null) ...[
              _SheetSection(
                icon: Icons.schedule_outlined,
                iconColor: AppColors.messier,
                title: '천문 정보',
                child: Column(
                  children: [
                    _InfoRow(label: '일출', value: _formatTime(w.sunrise)),
                    _InfoRow(label: '일몰', value: _formatTime(w.sunset)),
                    _InfoRow(
                      label: '천문박명 시작',
                      value: _formatTime(
                        w.sunrise.subtract(const Duration(minutes: 80)),
                      ),
                    ),
                    _InfoRow(
                      label: '천문박명 종료',
                      value: _formatTime(
                        w.sunset.add(const Duration(minutes: 80)),
                      ),
                    ),
                    _InfoRow(
                      label: '관측 가능 시작',
                      value: _formatTime(
                        w.sunset.add(const Duration(minutes: 80)),
                      ),
                    ),
                    if (condition.recommendedWindow.isNotEmpty)
                      _InfoRow(
                        label: '추천 관측시간',
                        value: condition.recommendedWindow,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ] else if (condition.recommendedWindow.isNotEmpty) ...[
              _SheetSection(
                icon: Icons.schedule_outlined,
                iconColor: AppColors.messier,
                title: '추천 관측시간',
                child: Text(
                  condition.recommendedWindow,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ],

            if (condition.stability != null) ...[
              _SheetSection(
                icon: Icons.insights_outlined,
                iconColor: AppColors.messier,
                title: '관측 안정성',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _StarsRow(count: condition.stability!.starCount),
                        const SizedBox(width: AppTheme.spacingSm),
                        Text(
                          condition.stability!.label,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      condition.stability!.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ],

            // 은하수 촬영 가능 시간
            _SheetSection(
              icon: Icons.auto_awesome,
              iconColor: AppColors.milky,
              title: '은하수 촬영 가능 시간',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    HomeViewModel.milkyWayWindow(now.month),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '* 은하수 핵 기준, 한국(37°N) 기준값입니다.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // 관측지수 산정 근거
            _SheetSection(
              icon: Icons.calculate_outlined,
              iconColor: AppColors.textSecondary,
              title: '관측지수 산정 근거',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (condition.hasTonightForecast) ...[
                    if (condition.isObservationFeasible)
                      for (final component in condition.qualityComponents)
                        _QualityRow(component: component)
                    else ...[
                      _InfoRow(
                        label: '평균 기온',
                        value:
                            '${condition.averageTemperature.toStringAsFixed(1)}°C',
                      ),
                      _InfoRow(
                        label: '평균 구름량',
                        value: '${condition.averageCloudCoverage.round()}%',
                      ),
                      _InfoRow(
                        label: '평균 풍속',
                        value:
                            '${condition.averageWindSpeed.toStringAsFixed(1)} m/s',
                      ),
                      _InfoRow(
                        label: '평균 강수확률',
                        value:
                            '${condition.averagePrecipitationPop.round()}%',
                      ),
                      _InfoRow(
                        label: '평균 가시거리',
                        value:
                            '${(condition.averageVisibilityMeters / 1000).toStringAsFixed(1)} km',
                      ),
                      if (condition.infeasibleUserMessage != null)
                        _InfoRow(
                          label: '관측 불가 사유',
                          value: condition.infeasibleUserMessage!,
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Text(
                        condition.isObservationFeasible
                            ? '※ 오늘 밤 관측 가능 시간대 평균 기준 (OQI)'
                            : '※ OpenWeather 예보 기준',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ] else
                    const _InfoRow(label: '예보', value: '미연동 (달만 반영)'),
                  const Divider(
                    height: 20,
                    color: AppColors.textSecondary,
                    thickness: 0.3,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '최종 관측지수',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        condition.isObservationFeasible
                            ? '${condition.score} / 100'
                            : '관측 불가',
                        style: TextStyle(
                          color: condition.isObservationFeasible
                              ? _scoreColor(condition.score)
                              : const Color(0xFFEF4444),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (condition.contributions.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.spacingMd),
                    const Text(
                      '점수 기여도',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...condition.contributions.map(
                      (item) => _ContributionRow(contribution: item),
                    ),
                  ],
                ],
              ),
            ),
            if (condition.tonightSlots.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingMd),
              const Center(
                child: Text(
                  '※ 가장 가까운 OpenWeather 예보를 사용합니다.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TonightObservationMatrix extends StatelessWidget {
  const _TonightObservationMatrix({
    required this.slots,
    required this.bestSlot,
    required this.observationWindow,
  });

  final List<TonightObservationSlot> slots;
  final TonightObservationSlot? bestSlot;
  final ObservationWindow? observationWindow;

  static const _labelWidth = 52.0;
  static const _cellWidth = 56.0;
  static const _rowHeight = 32.0;
  /// 관측 불가 배지가 들어가는 시간 행은 조금 더 높게.
  static const _timeRowHeight = 44.0;
  static const _borderColor = AppColors.textSecondary;

  static const _rowLabels = [
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

  bool _isInWindow(TonightObservationSlot slot) {
    final window = observationWindow;
    if (window == null) return false;
    return window.containsTime(slot.targetTime);
  }

  bool _isWindowStart(TonightObservationSlot slot) {
    final window = observationWindow;
    if (window == null) return false;
    return slot.targetTime == window.startTime;
  }

  bool _isWindowEnd(TonightObservationSlot slot) {
    final window = observationWindow;
    if (window == null) return false;
    return slot.targetTime == window.endTime;
  }

  BoxDecoration _cellDecoration(TonightObservationSlot slot) {
    if (!slot.canObserve) {
      return BoxDecoration(
        color: AppColors.textSecondary.withAlpha(24),
      );
    }

    final isBest = bestSlot?.targetTime == slot.targetTime;
    final inWindow = _isInWindow(slot);
    final isStart = _isWindowStart(slot);
    final isEnd = _isWindowEnd(slot);
    return BoxDecoration(
      color:
          isBest
              ? AppColors.ic.withAlpha(36)
              : inWindow
              ? const Color(0xFF60A5FA).withAlpha(24)
              : Colors.transparent,
      border:
          inWindow
              ? Border.all(
                color: const Color(0xFF60A5FA).withAlpha(
                  isStart || isEnd ? 180 : 120,
                ),
                width: isStart || isEnd ? 1.2 : 0.8,
              )
              : null,
    );
  }

  Widget _labelCell(String label, {required double height}) {
    return Container(
      height: height,
      width: _labelWidth,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _borderColor.withAlpha(40), width: 0.5),
        ),
      ),
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

  Widget _valueCell(
    TonightObservationSlot slot,
    Widget child, {
    bool emphasizeScore = false,
    double height = _rowHeight,
  }) {
    final isBest = bestSlot?.targetTime == slot.targetTime;
    final inactive = !slot.canObserve;
    return Container(
      height: height,
      width: _cellWidth,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      clipBehavior: Clip.hardEdge,
      decoration: _cellDecoration(slot).copyWith(
        border: Border(
          bottom: BorderSide(color: _borderColor.withAlpha(40), width: 0.5),
          left: BorderSide(color: _borderColor.withAlpha(40), width: 0.5),
        ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: inactive
              ? AppColors.textSecondary
              : emphasizeScore
                  ? _scoreColor(slot.score)
                  : AppColors.textPrimary,
          fontSize: 10,
          fontWeight: isBest ? FontWeight.bold : FontWeight.normal,
        ),
        child: child,
      ),
    );
  }

  Widget _infeasibleBadge(TonightObservationSlot slot) {
    final reason = slot.feasibility.reason;
    final shortReason = (reason != null && reason.isNotEmpty)
        ? reason
        : null;
    return Text(
      shortReason == null ? '불가' : '불가·$shortReason',
      style: const TextStyle(fontSize: 7, height: 1.05),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  List<Widget> _buildRowValues(int rowIndex) {
    return slots.map((slot) {
      final f = slot.forecast;
      final inactive = !slot.canObserve;

      if (rowIndex == 0) {
        return _valueCell(
          slot,
          height: _timeRowHeight,
          inactive
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      slot.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    _infeasibleBadge(slot),
                  ],
                )
              : Text(
                  slot.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        );
      }

      if (rowIndex == 9) {
        return _valueCell(
          slot,
          Text(inactive ? '불가' : slot.score.toString()),
          emphasizeScore: !inactive,
        );
      }

      if (rowIndex == 10) {
        return _valueCell(
          slot,
          Text(
            inactive ? '불가' : '★' * slot.starCount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          emphasizeScore: !inactive,
        );
      }

      return switch (rowIndex) {
        1 => _valueCell(
          slot,
          Text(f.weatherEmoji, style: const TextStyle(fontSize: 12)),
        ),
        2 => _valueCell(slot, Text('${f.temperature.round()}℃')),
        3 => _valueCell(slot, Text('${f.cloudCoverage}%')),
        4 => _valueCell(slot, Text(f.windSpeed.toStringAsFixed(1))),
        5 => _valueCell(slot, Text('${f.humidity}%')),
        6 => _valueCell(slot, Text('${f.pop.round()}%')),
        7 => _valueCell(
          slot,
          Text((f.visibility / 1000).toStringAsFixed(0)),
        ),
        8 => _valueCell(
          slot,
          Text(
            slot.condensationRisk.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _ => _valueCell(slot, const Text('-')),
      };
    }).toList();
  }

  double _heightForRow(int rowIndex) =>
      rowIndex == 0 ? _timeRowHeight : _rowHeight;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) {
      return const Text(
        '예보 데이터가 없습니다.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (observationWindow != null) _ObservationWindowCard(observationWindow!),
        if (observationWindow != null) const SizedBox(height: AppTheme.spacingMd),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                for (var i = 0; i < _rowLabels.length; i++)
                  _labelCell(_rowLabels[i], height: _heightForRow(i)),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: List.generate(
                    _rowLabels.length,
                    (rowIndex) => Row(
                      children: _buildRowValues(rowIndex),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ObservationWindowCard extends StatelessWidget {
  const _ObservationWindowCard(this.window);

  final ObservationWindow window;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        color: AppColors.ic.withAlpha(20),
        border: Border.all(color: AppColors.ic.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${'★' * window.starCount} 추천 관측시간',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            window.label,
            style: TextStyle(
              color: _scoreColor(window.averageScore),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '평균 관측지수 ${window.averageScore}점',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (window.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              '추천 이유',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            ...window.reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '· $reason',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContributionRow extends StatelessWidget {
  const _ContributionRow({required this.contribution});

  final ObservationScoreContribution contribution;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              contribution.category,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            '★' * contribution.starCount,
            style: const TextStyle(fontSize: 11, color: AppColors.solar),
          ),
          const Spacer(),
          Text(
            '+${contribution.points}',
            style: const TextStyle(
              color: AppColors.ic,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({required this.component});

  final ObservationQualityComponent component;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              component.category,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            component.starLabel,
            style: TextStyle(
              color: _scoreColor(component.qualityPoints),
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${component.qualityPoints}점',
            style: TextStyle(
              color: _scoreColor(component.qualityPoints),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── LIMITED 추천 안내 ────────────────────────────────────────────────────────

// ── 관측 불가 통합 안내 ───────────────────────────────────────────────────────

class _ObservationUnavailableNotice extends StatelessWidget {
  const _ObservationUnavailableNotice({required this.condition});

  final ObservationCondition condition;

  @override
  Widget build(BuildContext context) {
    final message = condition.statusUserMessage ?? condition.summaryText;
    final reason = condition.statusPrimaryReason;
    final isRain = condition.isRainUnavailable;
    final borderColor = isRain
        ? const Color(0xFFEF4444).withValues(alpha: 0.35)
        : AppColors.textSecondary.withValues(alpha: 0.25);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isRain ? Icons.water_drop_outlined : Icons.cloud_off_outlined,
                size: 18,
                color: isRain
                    ? const Color(0xFFEF4444)
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (reason != null && !message.contains(reason)) ...[
            const SizedBox(height: 6),
            Text(
              '대표 사유: $reason',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            '기상은 변할 수 있어 추천 대상과 촬영 순서는 참고용으로 계속 표시합니다.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _LimitedRecommendationNotice extends StatelessWidget {
  const _LimitedRecommendationNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingSm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            size: 16,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 추천 없음 위젯 ───────────────────────────────────────────────────────────

class _NoRecommendationWidget extends StatelessWidget {
  const _NoRecommendationWidget({required this.reasons});
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    final title = reasons.isNotEmpty &&
            reasons.first.contains('기상 조건')
        ? reasons.first
        : '추천 가능한 대상이 없습니다.';
    final detailReasons = reasons.isNotEmpty &&
            reasons.first.contains('기상 조건')
        ? reasons.skip(1).toList()
        : reasons;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.search_off_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (detailReasons.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingSm),
            const Text(
              '사유',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            ...detailReasons.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '· $r',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── ② 추천 대상 컴팩트 카드 ──────────────────────────────────────────────────

class _RecommendedObjectGrid extends StatelessWidget {
  const _RecommendedObjectGrid({
    required this.items,
    required this.onTap,
    required this.isPlanned,
    required this.equipmentChipsFor,
    required this.canAddToPlan,
    required this.onTogglePlan,
  });

  final List<RecommendationResult> items;
  final ValueChanged<RecommendationResult> onTap;
  final bool Function(String objectId) isPlanned;
  final CatalogEquipmentChips Function(String objectId) equipmentChipsFor;
  final bool Function(String objectId) canAddToPlan;
  final ValueChanged<String> onTogglePlan;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(
            bottom: i + 2 < items.length ? AppTheme.spacingXs : 0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _RecommendCompactCard(
                  recommended: items[i],
                  rank: i + 1,
                  onTap: () => onTap(items[i]),
                  isPlanned: isPlanned(items[i].object.id),
                  equipmentChips: equipmentChipsFor(items[i].object.id),
                  showPlanButton: canAddToPlan(items[i].object.id),
                  onTogglePlan: () => onTogglePlan(items[i].object.id),
                ),
              ),
              if (i + 1 < items.length) ...[
                const SizedBox(width: AppTheme.spacingXs),
                Expanded(
                  child: _RecommendCompactCard(
                    recommended: items[i + 1],
                    rank: i + 2,
                    onTap: () => onTap(items[i + 1]),
                    isPlanned: isPlanned(items[i + 1].object.id),
                    equipmentChips: equipmentChipsFor(items[i + 1].object.id),
                    showPlanButton: canAddToPlan(items[i + 1].object.id),
                    onTogglePlan: () => onTogglePlan(items[i + 1].object.id),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _RecommendCompactCard extends StatelessWidget {
  const _RecommendCompactCard({
    required this.recommended,
    required this.rank,
    required this.onTap,
    required this.isPlanned,
    required this.equipmentChips,
    required this.showPlanButton,
    required this.onTogglePlan,
  });

  final RecommendationResult recommended;
  final int rank;
  final VoidCallback onTap;
  final bool isPlanned;
  final CatalogEquipmentChips equipmentChips;
  final bool showPlanButton;
  final VoidCallback onTogglePlan;

  static const _dot = TextSpan(
    text: ' · ',
    style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
  );

  @override
  Widget build(BuildContext context) {
    final color = recommended.object.catalog.accentColor;
    final captured = recommended.object.captured;
    final w = recommended.observationWindow;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withAlpha(56), color.withAlpha(16)],
        ),
        border: Border.all(color: color.withAlpha(90), width: 1),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingSm,
        vertical: 6,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(
              right: showPlanButton ? 72 : 44,
            ),
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '#$rank',
                        style: TextStyle(
                          color: color.withAlpha(160),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          CatalogObjectDisplayFormatter.catalogTitle(
                            recommended.object,
                          ),
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (CatalogObjectDisplayFormatter.subtitleText(
                    recommended.object,
                  ).isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      CatalogObjectDisplayFormatter.subtitleText(
                        recommended.object,
                      ),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 10,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    '추천 ${'★' * recommended.starCount}',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!equipmentChips.isEmpty) ...[
                    const SizedBox(height: 3),
                    CatalogEquipmentChipsRow(chips: equipmentChips),
                  ],
                  const SizedBox(height: 2),
                  if (w != null)
                    Text.rich(
                      TextSpan(
                        children: [
                          if (w.feasibleWindowSummary != null)
                            TextSpan(
                              text: w.feasibleWindowSummary!,
                              style: TextStyle(
                                color: color.withAlpha(220),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else if (w.optimalStartTime != null &&
                              w.optimalEndTime != null)
                            TextSpan(
                              text:
                                  '${_formatTime(w.optimalStartTime!)}~${_formatTime(w.optimalEndTime!)}',
                              style: TextStyle(
                                color: color.withAlpha(200),
                                fontSize: 9,
                              ),
                            )
                          else if (w.recommendStartTime != null &&
                              w.observationEndTime != null)
                            TextSpan(
                              text:
                                  '${_formatTime(w.recommendStartTime!)}~${_formatTime(w.observationEndTime!)}',
                              style: TextStyle(
                                color: color.withAlpha(200),
                                fontSize: 9,
                              ),
                            ),
                          if (w.feasibleWindowSummary == null &&
                              w.peakAltitude != null) ...[
                            _dot,
                            TextSpan(
                              text: '최고고도 ${w.peakAltitude!.round()}°',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 9,
                              ),
                            ),
                          ],
                          _dot,
                          TextSpan(
                            text:
                                '달거리 ${recommended.moonSeparation.round()}°',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      captured
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 10,
                      color: captured ? color : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      captured ? '촬영' : '미촬영',
                      style: TextStyle(
                        color: captured ? color : AppColors.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (showPlanButton) ...[
                  const SizedBox(height: 3),
                  ShootingPlanActionButton(
                    isPlanned: isPlanned,
                    onToggle: onTogglePlan,
                    compact: true,
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


// ── 추천 상세 시트 ───────────────────────────────────────────────────────────

class _TodayEquipmentRecommendationBlock extends StatelessWidget {
  const _TodayEquipmentRecommendationBlock({required this.recommended});

  final RecommendationResult recommended;

  @override
  Widget build(BuildContext context) {
    final homeVm = context.watch<HomeViewModel>();
    final todayRec =
        homeVm.todayEquipmentRecommendationFor(recommended.object.id);
    if (todayRec == null) {
      return const SizedBox.shrink();
    }
    return TodayEquipmentRecommendationSection(recommendation: todayRec);
  }
}

class _RecommendDetailSheet extends StatelessWidget {
  const _RecommendDetailSheet({required this.recommended});
  final RecommendationResult recommended;

  @override
  Widget build(BuildContext context) {
    final homeVm = context.watch<HomeViewModel>();
    final color = recommended.object.catalog.accentColor;
    final captured = recommended.object.captured;
    final successRate = recommended.successRate.round();
    final equipmentChips =
        homeVm.todayEquipmentChipsFor(recommended.object.id);
    final isPlanned = homeVm.isPlanned(recommended.object.id);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.85,
      builder: (_, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacingXl,
          AppTheme.spacingLg,
          AppTheme.spacingXl,
          32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withAlpha(102),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingXl),
            Row(
              children: [
                Text(
                  CatalogObjectDisplayFormatter.catalogTitle(
                    recommended.object,
                  ),
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (CatalogObjectDisplayFormatter.subtitleText(
              recommended.object,
            ).isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingXs),
              Text(
                CatalogObjectDisplayFormatter.subtitleText(recommended.object),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppTheme.spacingSm),
            Row(
              children: [
                Text(
                  '추천 ${'★' * recommended.starCount}',
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '$successRate%',
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '성공률',
                        style: TextStyle(
                          color: color.withAlpha(180),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!equipmentChips.isEmpty) ...[
              const SizedBox(height: AppTheme.spacingSm),
              CatalogEquipmentChipsRow(chips: equipmentChips),
            ],
            if (homeVm.canAddToShootingPlan(recommended.object.id)) ...[
              const SizedBox(height: AppTheme.spacingSm),
              ShootingPlanActionButton(
                isPlanned: isPlanned,
                onToggle: () =>
                    homeVm.toggleTonightPlan(recommended.object.id),
              ),
            ],
            const SizedBox(height: AppTheme.spacingSm),
            SkyMapLocationButton(object: recommended.object),
            const SizedBox(height: AppTheme.spacingXl),

            if (recommended.observationWindow != null)
              _ObservationWindowSection(
                window: recommended.observationWindow!,
                moonSeparation: recommended.moonSeparation,
                exposureTimeLineLabel:
                    _resolveExposureTimeLineLabel(context, homeVm, recommended),
              ),
            if (recommended.observationWindow != null)
              const SizedBox(height: AppTheme.spacingMd),

            // 추천 이유 체크리스트
            _SheetSection(
              icon: Icons.auto_awesome,
              iconColor: AppColors.solar,
              title: '추천 이유',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMd,
                      vertical: AppTheme.spacingXs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.solar.withAlpha(38),
                      borderRadius:
                          BorderRadius.circular(AppTheme.spacingSm),
                    ),
                    child: Text(
                      '${recommended.season} 추천',
                      style: const TextStyle(
                        color: AppColors.solar,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  if (recommended.reasons.isNotEmpty)
                    ...recommended.reasons.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          r.label,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      recommended.reason,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),

            _TodayEquipmentRecommendationBlock(recommended: recommended),
            const SizedBox(height: AppTheme.spacingMd),

            // 천체 정보
            _SheetSection(
              icon: Icons.info_outline,
              iconColor: color,
              title: '천체 정보',
              child: Column(
                children: [
                  _InfoRow(label: '유형', value: recommended.object.displayType),
                  _InfoRow(
                    label: '별자리',
                    value: recommended.object.displayConstellation,
                  ),
                  _InfoRow(
                    label: '등급',
                    value: recommended.object.magnitude,
                  ),
                  _InfoRow(
                    label: '적경 (RA)',
                    value: recommended.object.ra,
                  ),
                  _InfoRow(
                    label: '적위 (Dec)',
                    value: recommended.object.dec,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // 촬영 여부
            _SheetSection(
              icon: captured
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              iconColor:
                  captured ? AppColors.ic : AppColors.textSecondary,
              title: '촬영 여부',
              child: Row(
                children: [
                  Icon(
                    captured
                        ? Icons.check_circle
                        : Icons.cancel_outlined,
                    color:
                        captured ? AppColors.ic : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: AppTheme.spacingSm),
                  Text(
                    captured ? '촬영 완료' : '미촬영',
                    style: TextStyle(
                      color: captured
                          ? AppColors.ic
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (captured &&
                      recommended.object.capturedDate != null) ...[
                    const SizedBox(width: AppTheme.spacingSm),
                    Text(
                      recommended.object.capturedDate!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 전체 추천 목록 시트 ──────────────────────────────────────────────────────

class _RecommendedListSheet extends StatelessWidget {
  const _RecommendedListSheet({
    required this.items,
    required this.month,
    this.title,
    this.canAddToPlan,
  });

  final List<RecommendationResult> items;
  final int month;
  final String? title;
  final bool Function(String objectId)? canAddToPlan;

  String _seasonText(int month) {
    if (month >= 3 && month <= 5) return '봄 하늘';
    if (month >= 6 && month <= 8) return '여름 하늘';
    if (month >= 9 && month <= 11) return '가을 하늘';
    return '겨울 하늘';
  }

  void _showDetail(BuildContext context, RecommendationResult rec) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RecommendDetailSheet(recommended: rec),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingXl,
              AppTheme.spacingLg,
              AppTheme.spacingXl,
              AppTheme.spacingMd,
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withAlpha(102),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingLg),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title ?? '오늘의 추천 대상',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          _seasonText(month),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '${items.length}개',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.background),
          Expanded(
            child: Consumer<HomeViewModel>(
              builder: (context, homeVm, _) {
                return ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.spacingMd,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (context, index) {
                    final rec = items[index];
                    final showPlan = canAddToPlan?.call(rec.object.id) ??
                        homeVm.canAddToShootingPlan(rec.object.id);
                    return _RecommendListTile(
                      recommended: rec,
                      rank: index + 1,
                      onTap: () => _showDetail(context, rec),
                      isPlanned: homeVm.isPlanned(rec.object.id),
                      equipmentChips:
                          homeVm.todayEquipmentChipsFor(rec.object.id),
                      showPlanButton: showPlan,
                      onTogglePlan: () =>
                          homeVm.toggleTonightPlan(rec.object.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


class _RecommendListTile extends StatelessWidget {
  const _RecommendListTile({
    required this.recommended,
    required this.rank,
    required this.onTap,
    required this.isPlanned,
    required this.equipmentChips,
    required this.showPlanButton,
    required this.onTogglePlan,
  });

  final RecommendationResult recommended;
  final int rank;
  final VoidCallback onTap;
  final bool isPlanned;
  final CatalogEquipmentChips equipmentChips;
  final bool showPlanButton;
  final VoidCallback onTogglePlan;

  static const _dot = TextSpan(
    text: ' · ',
    style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
  );

  @override
  Widget build(BuildContext context) {
    final color = recommended.object.catalog.accentColor;
    final captured = recommended.object.captured;
    final w = recommended.observationWindow;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg,
          vertical: AppTheme.spacingSm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: AppTheme.spacingMd),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingSm,
                vertical: AppTheme.spacingXs,
              ),
              decoration: BoxDecoration(
                color: color.withAlpha(51),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                recommended.object.catalog.label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 줄 1: 카탈로그명 · 촬영여부 / 줄 2: Display Name(Object Type)
                  Row(
                    children: [
                      Text(
                        CatalogObjectDisplayFormatter.catalogTitle(
                          recommended.object,
                        ),
                        style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        captured
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 10,
                        color: captured ? color : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        captured ? '촬영' : '미촬영',
                        style: TextStyle(
                          color: captured ? color : AppColors.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                  if (CatalogObjectDisplayFormatter.subtitleText(
                    recommended.object,
                  ).isNotEmpty)
                    Text(
                      CatalogObjectDisplayFormatter.subtitleText(
                        recommended.object,
                      ),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 3),
                  Text(
                    '추천 ${'★' * recommended.starCount}',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!equipmentChips.isEmpty) ...[
                    const SizedBox(height: 3),
                    CatalogEquipmentChipsRow(chips: equipmentChips),
                  ],
                  const SizedBox(height: 2),
                  if (w != null)
                    Text.rich(
                      TextSpan(
                        children: [
                          if (w.feasibleWindowSummary != null)
                            TextSpan(
                              text: w.feasibleWindowSummary!,
                              style: TextStyle(
                                color: color.withAlpha(220),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else if (w.optimalStartTime != null &&
                              w.optimalEndTime != null)
                            TextSpan(
                              text:
                                  '${_formatTime(w.optimalStartTime!)}~${_formatTime(w.optimalEndTime!)}',
                              style: TextStyle(
                                color: color.withAlpha(200),
                                fontSize: 10,
                              ),
                            )
                          else if (w.recommendStartTime != null &&
                              w.observationEndTime != null)
                            TextSpan(
                              text:
                                  '${_formatTime(w.recommendStartTime!)}~${_formatTime(w.observationEndTime!)}',
                              style: TextStyle(
                                color: color.withAlpha(200),
                                fontSize: 10,
                              ),
                            ),
                          if (w.feasibleWindowSummary == null &&
                              w.peakAltitude != null) ...[
                            _dot,
                            TextSpan(
                              text: '최고고도 ${w.peakAltitude!.round()}°',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                          _dot,
                          TextSpan(
                            text: '달거리 ${recommended.moonSeparation.round()}°',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      recommended.object.displayType,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
            if (showPlanButton)
              ShootingPlanActionButton(
                isPlanned: isPlanned,
                onToggle: onTogglePlan,
                compact: true,
              ),
            const SizedBox(width: AppTheme.spacingXs),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ── ③ 카테고리 진행현황 카드 ─────────────────────────────────────────────────

class _CategoryProgressCard extends StatelessWidget {
  const _CategoryProgressCard({
    required this.progress,
    this.compact = false,
  });

  final CategoryProgress progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = progress.type.accentColor;
    final percent = progress.progressPercent;
    final label = _catalogLabel(progress.type);
    final verticalPadding =
        compact ? AppTheme.spacingSm : AppTheme.spacingMd;
    final titleSize = compact ? 12.0 : 14.0;
    final statSize = compact ? 11.0 : 12.0;
    final percentSize = compact ? 12.0 : 13.0;
    final progressHeight = compact ? 6.0 : 8.0;

    return GestureDetector(
      onTap: () {
        context
            .read<AppNavigationNotifier>()
            .navigateToCatalog(progress.type);
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      Container(
                        width: compact ? 7 : 9,
                        height: compact ? 7 : 9,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingSm),
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${progress.captured}/${progress.total}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: statSize,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${percent.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: color,
                        fontSize: percentSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: compact ? 6 : AppTheme.spacingSm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.progress,
                minHeight: progressHeight,
                backgroundColor: color.withAlpha(38),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 스케줄 없음 위젯 ───────────────────────────────────────────────────────────

class _ScheduleEmptyWidget extends StatelessWidget {
  const _ScheduleEmptyWidget({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.ic.withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timeline, color: AppColors.ic, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
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

// ── 관측 세션 타임라인 ──────────────────────────────────────────────────────────

class _ObservationSessionTimeline extends StatelessWidget {
  const _ObservationSessionTimeline({
    required this.items,
    required this.onTap,
    required this.onEdit,
  });

  final List<ScheduleItem> items;
  final void Function(RecommendationResult result) onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.ic.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, color: AppColors.ic, size: 16),
              const SizedBox(width: 6),
              Text(
                '오늘 밤 촬영 순서',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '촬영 순서 편집',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onEdit,
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${visibleItems.length}개',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < visibleItems.length; i++) ...[
                  _SessionTableCell(
                    item: visibleItems[i],
                    onTap: () => onTap(visibleItems[i].result),
                  ),
                  if (i < visibleItems.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(top: 28, left: 2, right: 2),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: AppColors.textSecondary,
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

class _SessionTableCell extends StatelessWidget {
  const _SessionTableCell({
    required this.item,
    required this.onTap,
  });

  final ScheduleItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = item.catalogObject.catalog.accentColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 118,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingSm,
          vertical: AppTheme.spacingXs,
        ),
        decoration: BoxDecoration(
          color: color.withAlpha(24),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(70)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_formatTime(item.startTime)} ~ ${_formatTime(item.endTime)}',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              CatalogObjectDisplayFormatter.catalogTitle(item.catalogObject),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (CatalogObjectDisplayFormatter.subtitleText(item.catalogObject)
                .isNotEmpty)
              Text(
                CatalogObjectDisplayFormatter.subtitleText(item.catalogObject),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Text(
              item.durationLabel,
              style: TextStyle(
                color: color.withAlpha(180),
                fontSize: 9,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '★' * item.starCount,
              style: TextStyle(
                color: color.withAlpha(200),
                fontSize: 9,
              ),
            ),
            Text(
              item.status.label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 관측 시간 정보 섹션 ──────────────────────────────────────────────────────

class _ObservationWindowSection extends StatelessWidget {
  const _ObservationWindowSection({
    required this.window,
    required this.moonSeparation,
    this.exposureTimeLineLabel,
  });

  final ObjectObservationWindow window;
  final double moonSeparation;
  final String? exposureTimeLineLabel;

  @override
  Widget build(BuildContext context) {
    return _SheetSection(
      icon: Icons.access_time_outlined,
      iconColor: AppColors.ic,
      title: '오늘 밤 관측 정보',
      child: Column(
        children: [
          if (window.feasibleWindowSummary != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd,
                  vertical: AppTheme.spacingSm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.solar.withAlpha(38),
                  borderRadius: BorderRadius.circular(AppTheme.spacingXs),
                ),
                child: Text(
                  window.feasibleWindowSummary!,
                  style: const TextStyle(
                    color: AppColors.solar,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          _InfoRow(
            label: '현재 고도',
            value: '${window.currentAltitude.round()}°',
          ),
          _InfoRow(
            label: '현재 방위각',
            value: '${window.currentAzimuth.round()}°',
          ),
          if (window.recommendStartTime != null)
            _InfoRow(
              label: '추천 시작',
              value: _formatTime(window.recommendStartTime!),
            ),
          if (window.optimalStartTime != null && window.optimalEndTime != null)
            _InfoRow(
              label: '최적 시간',
              value:
                  '${_formatTime(window.optimalStartTime!)} ~ ${_formatTime(window.optimalEndTime!)}',
            ),
          if (window.peakAltitude != null && window.peakAltitudeTime != null)
            _InfoRow(
              label: '최고 고도',
              value:
                  '${window.peakAltitude!.round()}° (${_formatTime(window.peakAltitudeTime!)})',
            ),
          if (exposureTimeLineLabel != null)
            _InfoRow(
              label: '촬영시간(최소/권장)',
              value: exposureTimeLineLabel!,
            ),
          _InfoRow(
            label: '달과 거리',
            value: '${moonSeparation.round()}°',
          ),
          if (window.observationEndTime != null)
            _InfoRow(
              label: '관측 종료',
              value: _formatTime(window.observationEndTime!),
            ),
          _InfoRow(
            label: '총 관측 시간',
            value: window.totalObservableLabel,
          ),
          if (window.isCurrentlyVisible)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd,
                  vertical: AppTheme.spacingXs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.ic.withAlpha(38),
                  borderRadius: BorderRadius.circular(AppTheme.spacingXs),
                ),
                child: const Text(
                  '현재 관측 가능',
                  style: TextStyle(
                    color: AppColors.ic,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 공통 위젯 ────────────────────────────────────────────────────────────────

class _SheetSection extends StatelessWidget {
  const _SheetSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSm),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShootingOrderEditSheet extends StatefulWidget {
  const _ShootingOrderEditSheet({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  State<_ShootingOrderEditSheet> createState() =>
      _ShootingOrderEditSheetState();
}

class _ShootingOrderEditSheetState extends State<_ShootingOrderEditSheet> {
  late List<ScheduleItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List<ScheduleItem>.from(widget.viewModel.scheduleItems);
  }

  Future<void> _applyReorder(int oldIndex, int newIndex) async {
    await widget.viewModel.reorderTonightPlan(oldIndex, newIndex);
    if (!mounted) return;
    setState(() {
      _items = List<ScheduleItem>.from(widget.viewModel.scheduleItems);
    });
  }

  Future<void> _removeAt(int index) async {
    final objectId = _items[index].target.object.id;
    setState(() => _items.removeAt(index));
    await widget.viewModel.toggleTonightPlan(objectId);
    if (!mounted) return;
    if (_items.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _resetToRecommended() async {
    await widget.viewModel.resetTonightPlanToRecommended();
    if (!mounted) return;
    setState(() {
      _items = List<ScheduleItem>.from(widget.viewModel.scheduleItems);
    });
    if (_items.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacingLg,
          AppTheme.spacingMd,
          AppTheme.spacingLg,
          AppTheme.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '오늘 밤 촬영 순서 편집',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingXs),
            const Text(
              '드래그하여 순서를 바꾸거나 항목을 삭제할 수 있습니다. '
              '추천 대상은 하루에 한 번 자동으로 갱신됩니다.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                onReorderItem: (oldIndex, newIndex) async {
                  await _applyReorder(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final color = item.catalogObject.catalog.accentColor;
                  return ListTile(
                    key: ValueKey(item.target.object.id),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: Icon(Icons.drag_handle, color: color),
                    ),
                    title: Text(
                      CatalogObjectDisplayFormatter.catalogTitle(
                        item.catalogObject,
                      ),
                    ),
                    subtitle: Text(
                      CatalogObjectDisplayFormatter.subtitleText(
                        item.catalogObject,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: '목록에서 제거',
                      icon: const Icon(Icons.remove_circle_outline),
                      color: Colors.redAccent,
                      onPressed: () => _removeAt(index),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            OutlinedButton.icon(
              onPressed: _resetToRecommended,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('추천 순서로 되돌리기'),
            ),
          ],
        ),
      ),
    );
  }
}
