import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/app_navigation_notifier.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../features/catalog/view/catalog_screen.dart';
import '../../features/catalog/viewmodel/catalog_view_model.dart';
import '../../features/desktop/view/pc_photo_registration_screen.dart';
import '../../features/gallery/view/gallery_screen.dart';
import '../../features/gallery/viewmodel/gallery_view_model.dart';
import '../../features/light_pollution_map/view/light_pollution_map_screen.dart';
import '../../features/light_pollution_map/viewmodel/light_pollution_map_view_model.dart';
import '../../features/settings/view/settings_screen.dart';
import '../../features/sky_map/view/sky_map_screen.dart';
import '../../features/sky_map/viewmodel/sky_map_view_model.dart';
import '../../features/stats/view/stats_screen.dart';
import '../../features/stats/viewmodel/stats_view_model.dart';

/// Windows 전용 상단 내비게이션 Shell.
///
/// 메뉴 index 1~5는 기존 [AppNavigationNotifier] 계약을 그대로 사용해
/// Catalog/성도 내부의 화면 전환 요청도 모바일과 같은 대상으로 연결한다.
class PcMainShell extends StatefulWidget {
  const PcMainShell({super.key});

  @override
  State<PcMainShell> createState() => _PcMainShellState();
}

class _PcMainShellState extends State<PcMainShell> {
  static const _settingsIndex = 6;
  static const _screenCount = 7;

  AppNavigationNotifier? _navigation;
  final _navigatorKeys = List<GlobalKey<NavigatorState>>.generate(
    _screenCount,
    (_) => GlobalKey<NavigatorState>(),
  );

  late final _pages = <Widget>[
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[0],
      child: const PcPhotoRegistrationScreen(),
    ),
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[1],
      child: const CatalogScreen(),
    ),
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[2],
      child: const GalleryScreen(),
    ),
    const SizedBox.shrink(),
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[4],
      child: const SkyMapScreen(),
    ),
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[5],
      child: const StatsScreen(),
    ),
    _PcTabNavigator(
      navigatorKey: _navigatorKeys[6],
      child: const SettingsScreen(),
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

  void _selectMenu(int index) {
    _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    _ensureLoaded(index);
    _navigation!.navigateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final navigation = context.read<AppNavigationNotifier>();
    return Scaffold(
      body: Column(
        children: [
          _PcTopNavigation(
            listenable: navigation,
            onSelected: _selectMenu,
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
                    _pages[_settingsIndex],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PcTopNavigation extends StatelessWidget {
  const _PcTopNavigation({required this.listenable, required this.onSelected});

  final AppNavigationNotifier listenable;
  final ValueChanged<int> onSelected;

  static const _items = <({int index, String label, IconData icon})>[
    (index: 0, label: '사진 등록', icon: Icons.add_photo_alternate_outlined),
    (index: 1, label: '천체 카탈로그', icon: Icons.grid_view_outlined),
    (index: 2, label: '갤러리', icon: Icons.photo_library_outlined),
    (index: 3, label: '광해지도', icon: Icons.map_outlined),
    (index: 4, label: '성도', icon: Icons.explore_outlined),
    (index: 5, label: '통계', icon: Icons.bar_chart_outlined),
    (index: 6, label: '설정', icon: Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 58,
          child: ListenableBuilder(
            listenable: listenable,
            builder: (context, _) {
              final selected = listenable.currentIndex;
              return Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppTheme.spacingLg),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome, color: AppColors.solar, size: 20),
                        SizedBox(width: AppTheme.spacingSm),
                        Text('AstroJournal', style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSm),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: AppTheme.spacingXs),
                      itemBuilder: (context, itemIndex) {
                        final item = _items[itemIndex];
                        final isSelected = selected == item.index;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: TextButton.icon(
                            onPressed: () => onSelected(item.index),
                            icon: Icon(item.icon, size: 18),
                            label: Text(item.label),
                            style: TextButton.styleFrom(
                              foregroundColor: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                              backgroundColor: isSelected ? AppColors.messier.withValues(alpha: 0.18) : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
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
