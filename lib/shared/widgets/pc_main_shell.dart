import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/app_navigation_notifier.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/pc_design.dart';
import '../../features/catalog/view/catalog_screen.dart';
import '../../features/catalog/viewmodel/catalog_view_model.dart';
import '../../features/desktop/view/pc_photo_registration_screen.dart';
import '../../features/gallery/view/gallery_screen.dart';
import '../../features/gallery/viewmodel/gallery_view_model.dart';
import '../../features/home/view/pc_home_screen.dart';
import '../../features/home/view/astronomy_events_screen.dart';
import '../../features/light_pollution_map/view/light_pollution_map_screen.dart';
import '../../features/light_pollution_map/viewmodel/light_pollution_map_view_model.dart';
import '../../features/settings/view/settings_screen.dart';
import '../../features/sky_map/view/sky_map_screen.dart';
import '../../features/sky_map/viewmodel/sky_map_view_model.dart';
import '../../features/stats/view/stats_screen.dart';
import '../../features/stats/viewmodel/stats_view_model.dart';
import '../../features/season/view/season_planner_screen.dart';
import '../../features/season/viewmodel/season_planner_view_model.dart';
import 'observatory_ui.dart';

/// Windows 전용 사이드바 내비게이션 Shell.
///
/// 메뉴 index 0~5는 기존 [AppNavigationNotifier] 계약을 그대로 사용해
/// Catalog/성도 내부의 화면 전환 요청도 모바일과 같은 대상으로 연결한다.
class PcMainShell extends StatefulWidget {
  const PcMainShell({super.key});

  @override
  State<PcMainShell> createState() => _PcMainShellState();
}

class _PcMainShellState extends State<PcMainShell> {
  static const _photoRegistrationIndex = 6;
  static const _settingsIndex = 7;
  static const _screenCount = 8;

  AppNavigationNotifier? _navigation;
  int _lastNavigationIndex = 0;
  String _selectedSidebarAction = 'home';
  final _navigatorKeys = List<GlobalKey<NavigatorState>>.generate(
    _screenCount,
    (_) => GlobalKey<NavigatorState>(),
  );

  late final _pages = <Widget>[
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[0],
      child: Theme(
        data: AppTheme.observatoryDark,
        child: const PcHomeScreen(),
      ),
    ),
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[1],
      child: const CatalogScreen(),
    ),
    Theme(
      data: AppTheme.observatoryDark,
      child: _PcTabNavigator(
        navigatorKey: _navigatorKeys[2],
        child: const GalleryScreen(showHomeNavigation: true),
      ),
    ),
    const SizedBox.shrink(),
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[4],
      child: const SkyMapScreen(),
    ),
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[5],
      child: const StatsScreen(pcSections: true),
    ),
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[6],
      child: const PcPhotoRegistrationScreen(),
    ),
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[7],
      child: const SettingsScreen(pcSections: true),
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = context.read<AppNavigationNotifier>();
    if (_navigation == navigation) return;
    _navigation?.removeListener(_onNavigationChanged);
    _navigation = navigation..addListener(_onNavigationChanged);
  }

  @override
  void dispose() {
    _navigation?.removeListener(_onNavigationChanged);
    super.dispose();
  }

  void _onNavigationChanged() {
    if (!mounted) return;
    final index = _navigation!.currentIndex.clamp(0, _screenCount - 1);
    if (index != _lastNavigationIndex) {
      setState(() {
        _selectedSidebarAction = switch (index) {
          1 => 'catalog',
          2 => 'gallery',
          3 => 'map',
          4 => 'sky',
          5 => 'stats',
          6 => 'photo',
          7 => 'settings',
          _ => 'home',
        };
        _lastNavigationIndex = index;
      });
    }
    _ensureLoaded(index);
  }

  void _ensureLoaded(int index) {
    switch (index) {
      case 1:
        final catalog = context.read<CatalogViewModel>();
        if (!catalog.hasLoaded) {
          unawaited(catalog.load());
        } else {
          // Windows startup에서는 목록만 먼저 읽고, 전체 검색 인덱스와
          // 장비 chip 계산은 Catalog 탭을 실제로 열 때 시작한다.
          unawaited(catalog.finishDeferredHeavyWork());
        }
      case 2:
        final gallery = context.read<GalleryViewModel>();
        if (!gallery.hasLoaded) unawaited(gallery.load());
      case 3:
        final map = context.read<LightPollutionMapViewModel>();
        if (!map.hasLoaded) unawaited(map.load());
      case 4:
        final skyMap = context.read<SkyMapViewModel>();
        if (!skyMap.hasLoaded) unawaited(skyMap.load());
      case 5:
        final stats = context.read<StatsViewModel>();
        if (!stats.hasLoaded) unawaited(stats.load());
      default:
        break;
    }
  }

  void _selectMenu(int index, {required String action}) {
    _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    _ensureLoaded(index);
    setState(() {
      _selectedSidebarAction = action;
      _lastNavigationIndex = index;
    });
    _navigation!.navigateTo(index);
  }

  void _selectSidebarAction(String action) {
    final index = switch (action) {
      'catalog' => 1,
      'gallery' => 2,
      'map' => 3,
      'sky' => 4,
      'stats' || 'stats_monthly' || 'stats_targets' => 5,
      'photo' => 6,
      'settings' || 'settings_recommendations' || 'settings_sites' ||
      'settings_equipment' || 'settings_connection' || 'settings_backup' ||
      'settings_reset' => 7,
      _ => 0,
    };
    _selectMenu(index, action: action);
    if (action != 'season' && action != 'month' && action != 'events') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nestedContext = _navigatorKeys[0].currentState?.overlay?.context;
      if (nestedContext == null) return;
      final route = action == 'events'
          ? AstronomyEventsScreen.open(nestedContext, showHomeNavigation: true)
          : SeasonPlannerScreen.open(
              nestedContext,
              initialViewMode: action == 'month'
                  ? SeasonPlannerViewMode.byMonth
                  : SeasonPlannerViewMode.bySeason,
              fixedViewMode: true,
            );
      unawaited(route.whenComplete(() {
        if (mounted && _selectedSidebarAction == action) {
          setState(() => _selectedSidebarAction = 'home');
        }
      }));
    });
  }

  @override
  Widget build(BuildContext context) {
    final navigation = context.read<AppNavigationNotifier>();
    return Theme(
      data: AppTheme.pcDark,
      child: Scaffold(
        backgroundColor: PcDesign.background,
        body: LayoutBuilder(
          builder: (context, _) => Row(
            children: [
              SizedBox(
                width: 190,
                child: _PcSidebar(
                  selectedAction: _selectedSidebarAction,
                  onSelected: _selectSidebarAction,
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: navigation,
                  builder: (context, _) {
                    final index =
                        navigation.currentIndex.clamp(0, _screenCount - 1);
                    return IndexedStack(
                      index: index,
                      children: [
                        _pages[0],
                        _pages[1],
                        _pages[2],
                        LightPollutionMapScreen(isActive: index == 3),
                        _pages[4],
                        _pages[5],
                        _pages[_photoRegistrationIndex],
                        _pages[_settingsIndex],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PcSidebar extends StatefulWidget {
  const _PcSidebar({required this.selectedAction, required this.onSelected});

  final String selectedAction;
  final ValueChanged<String> onSelected;

  @override
  State<_PcSidebar> createState() => _PcSidebarState();
}

class _PcSidebarState extends State<_PcSidebar> {
  String? _expandedSection;

  @override
  void didUpdateWidget(covariant _PcSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sectionOf(oldWidget.selectedAction) !=
        _sectionOf(widget.selectedAction)) {
      _expandedSection = null;
    }
  }

  String _sectionOf(String action) {
    if (action == 'home') return 'home';
    if (action == 'photo') return 'photo';
    if (action == 'catalog' || action == 'gallery') return 'library';
    if (action.startsWith('stats')) return 'analysis';
    if (action.startsWith('settings')) return 'settings';
    return 'observation';
  }

  @override
  Widget build(BuildContext context) {
    final selectedSection = _sectionOf(widget.selectedAction);
    final expanded = _expandedSection ?? selectedSection;
    return Material(
      color: PcDesign.background,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 22, 12, 22),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_outlined,
                      color: PcDesign.secondary, size: 27),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text('AstroJournal',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: PcDesign.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: PcDesign.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
                children: [
                  _section('home', '홈', Icons.home_outlined, 'home', const []),
                    _section('observation', '관측', Icons.travel_explore_outlined,
                      'sky', const [
                    ('sky', '성도'),
                    ('map', '관측지 / 광해'),
                    ('season', '계절별 계획'),
                    ('month', '월별 계획'),
                    ('events', '천문 이벤트'),
                  ], expanded: expanded),
                  _section('library', '천체와 사진', Icons.photo_library_outlined,
                      'catalog', const [
                    ('catalog', '천체 카탈로그'),
                    ('gallery', '내 사진 갤러리'),
                  ], expanded: expanded),
                  _section('analysis', '촬영 분석', Icons.bar_chart_outlined,
                      'stats', const [], expanded: expanded),
                  _section('settings', '설정', Icons.settings_outlined,
                      'settings', const [], expanded: expanded),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
              child: SizedBox(
                width: double.infinity,
                child: ObservatoryButton(
                  label: '사진 등록',
                  icon: Icons.add_a_photo_outlined,
                  primary: true,
                  backgroundColor: PcDesign.accent,
                  borderColor: PcDesign.accent,
                  foregroundColor: PcDesign.background,
                  onPressed: () => widget.onSelected('photo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    String id,
    String label,
    IconData icon,
    String defaultAction,
    List<(String, String)> children, {
    String? expanded,
  }) {
    final selected = _sectionOf(widget.selectedAction) == id;
    final isExpanded = expanded == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        children: [
          Material(
            color: selected
                ? PcDesign.raised
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: ListTile(
              dense: true,
              minLeadingWidth: 20,
              contentPadding: const EdgeInsets.symmetric(horizontal: 11),
              leading: Icon(icon,
                  color: selected
                      ? PcDesign.secondary
                      : PcDesign.muted),
              title: Text(label,
                  style: TextStyle(
                    color: selected
                        ? PcDesign.text
                        : PcDesign.muted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  )),
              trailing: children.isEmpty
                  ? null
                  : Icon(isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: PcDesign.muted),
              onTap: () {
                setState(() => _expandedSection = id);
                widget.onSelected(defaultAction);
              },
            ),
          ),
          if (isExpanded)
            for (final child in children)
              Padding(
                padding: const EdgeInsets.only(left: 19, top: 2),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.only(left: 12, right: 8),
                  title: Text(child.$2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.selectedAction == child.$1
                            ? PcDesign.secondary
                            : PcDesign.muted,
                      )),
                  onTap: () => widget.onSelected(child.$1),
                ),
              ),
        ],
      ),
    );
  }
}

class _PcTabNavigator extends StatelessWidget {
  const _PcTabNavigator({required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        builder: (_) => child,
        settings: settings,
      ),
    );
  }
}
