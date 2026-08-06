import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/app_navigation_notifier.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/catalog_object.dart';
import '../../features/catalog/view/catalog_screen.dart';
import '../../features/catalog/viewmodel/catalog_view_model.dart';
import '../../features/gallery/view/gallery_screen.dart';
import '../../features/gallery/viewmodel/gallery_view_model.dart';
import '../../features/home/view/home_screen.dart';
import '../../features/main/viewmodel/main_back_navigation_view_model.dart';
import '../../features/photo_first/photo_first_registration_flow.dart';
import '../../features/photo_first/viewmodel/photo_first_registration_view_model.dart';
import '../../features/light_pollution_map/view/light_pollution_map_screen.dart';
import '../../features/light_pollution_map/viewmodel/light_pollution_map_view_model.dart';
import '../../features/sky_map/view/sky_map_screen.dart';
import '../../features/sky_map/viewmodel/sky_map_view_model.dart';
import '../../features/stats/view/stats_screen.dart';
import '../../features/stats/viewmodel/stats_view_model.dart';

/// GNB 탭 인덱스:
/// 0=홈, 1=카탈로그, 2=갤러리, 3=광해지도, 4=성도, 5=통계 (+ nav 6=사진등록 액션)
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  AppNavigationNotifier? _navNotifier;

  static const int _photoRegistrationNavIndex = 6;
  static const int _screenCount = 6;

  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    _screenCount,
    (_) => GlobalKey<NavigatorState>(),
  );

  /// 탭 본문은 한 번만 만들어 IndexedStack이 동일 인스턴스를 유지하게 한다.
  late final List<Widget> _tabNavigators = [
    _TabNavigator(
      navigatorKey: _navigatorKeys[0],
      child: const HomeScreen(),
    ),
    _TabNavigator(
      navigatorKey: _navigatorKeys[1],
      child: const CatalogScreen(),
    ),
    _TabNavigator(
      navigatorKey: _navigatorKeys[2],
      child: const GalleryScreen(),
    ),
    const SizedBox.shrink(), // 광해지도는 isActive 때문에 아래에서 따로 구성
    _TabNavigator(
      navigatorKey: _navigatorKeys[4],
      child: const SkyMapScreen(),
    ),
    _TabNavigator(
      navigatorKey: _navigatorKeys[5],
      child: const StatsScreen(),
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = context.read<AppNavigationNotifier>();
    if (_navNotifier != notifier) {
      _navNotifier?.removeListener(_onNavChanged);
      _navNotifier = notifier;
      _navNotifier!.addListener(_onNavChanged);
    }
  }

  @override
  void dispose() {
    _navNotifier?.removeListener(_onNavChanged);
    super.dispose();
  }

  void _onNavChanged() {
    if (!mounted) return;
    final screenIndex = _navNotifier?.currentIndex ?? 0;
    _ensureTabLoaded(screenIndex);

    final pending = _navNotifier?.pendingCatalogType;
    if (pending != null) {
      _ensureTabLoaded(1);
      context.read<CatalogViewModel>().selectTab(pending);
      _navNotifier?.consumePendingCatalogType();
    }

    final pendingSkyObject = _navNotifier?.pendingSkyMapObject;
    if (pendingSkyObject != null) {
      final object = _navNotifier!.consumePendingSkyMapObject()!;
      unawaited(_focusSkyMapObject(object));
    }
  }

  Future<void> _focusSkyMapObject(CatalogObject object) async {
    _ensureTabLoaded(4);
    final skyMap = context.read<SkyMapViewModel>();
    if (!skyMap.hasLoaded) {
      await skyMap.load();
    }
    if (!mounted) return;
    skyMap.focusObjectLocation(object);
  }

  void _ensureTabLoaded(int screenIndex) {
    switch (screenIndex) {
      case 1:
        final catalog = context.read<CatalogViewModel>();
        if (!catalog.hasLoaded) unawaited(catalog.load());
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

  Future<void> _onPhotoRegistrationTap() async {
    final photoVm = context.read<PhotoFirstRegistrationViewModel>();
    if (photoVm.isProcessing) return;
    await runPhotoFirstRegistrationFlow(context);
  }

  void _handleBack(bool didPop) {
    final screenIndex = context.read<AppNavigationNotifier>().currentIndex;
    final backVm = context.read<MainBackNavigationViewModel>();

    final action = backVm.handleBackRequest(
      currentTabIndex: screenIndex,
      navigatorKeys: _navigatorKeys,
      didPop: didPop,
    );

    switch (action) {
      case MainBackAction.showExitHint:
        _showExitHint();
      case MainBackAction.exitApp:
        SystemNavigator.pop();
      case MainBackAction.poppedNested:
      case MainBackAction.navigateHome:
      case MainBackAction.none:
        break;
    }
  }

  void _showExitHint() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(MainBackNavigationViewModel.exitHintMessage),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.read<AppNavigationNotifier>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _handleBack(didPop),
      child: Scaffold(
        // 탭 전환 시 IndexedStack 자식 인스턴스를 유지해 숨은 탭 재빌드를 막는다.
        body: ListenableBuilder(
          listenable: nav,
          builder: (context, _) {
            final screenIndex = nav.currentIndex.clamp(0, _screenCount - 1);
            return IndexedStack(
              index: screenIndex,
              children: [
                _tabNavigators[0],
                _tabNavigators[1],
                _tabNavigators[2],
                LightPollutionMapScreen(isActive: screenIndex == 3),
                _tabNavigators[4],
                _tabNavigators[5],
              ],
            );
          },
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: nav,
          builder: (context, _) {
            final screenIndex = nav.currentIndex.clamp(0, _screenCount - 1);
            return Selector<PhotoFirstRegistrationViewModel, bool>(
              selector: (_, vm) => vm.isProcessing,
              builder: (context, isProcessing, _) {
                return NavigationBar(
                  selectedIndex: screenIndex,
                  onDestinationSelected: (navIndex) {
                    if (navIndex == _photoRegistrationNavIndex) {
                      _onPhotoRegistrationTap();
                      return;
                    }

                    final targetScreen = navIndex;
                    _navigatorKeys[targetScreen].currentState
                        ?.popUntil((route) => route.isFirst);
                    context
                        .read<MainBackNavigationViewModel>()
                        .resetExitState();
                    final mapVm = context.read<LightPollutionMapViewModel>();
                    final mapAlreadyLoaded = mapVm.hasLoaded;
                    _ensureTabLoaded(targetScreen);
                    nav.navigateTo(targetScreen);
                    if (targetScreen == 3 && mapAlreadyLoaded) {
                      unawaited(mapVm.refreshCurrentLocation());
                    }
                  },
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: '홈',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.grid_view_outlined),
                      selectedIcon: Icon(Icons.grid_view),
                      label: '카탈로그',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.photo_library_outlined),
                      selectedIcon: Icon(Icons.photo_library),
                      label: '갤러리',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.map_outlined),
                      selectedIcon: Icon(Icons.map),
                      label: '광해지도',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore),
                      label: '성도',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.bar_chart_outlined),
                      selectedIcon: Icon(Icons.bar_chart),
                      label: '통계',
                    ),
                    NavigationDestination(
                      icon: isProcessing
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.add_photo_alternate_outlined,
                              color: isProcessing
                                  ? AppColors.textSecondary
                                  : AppColors.solar,
                            ),
                      selectedIcon: const Icon(
                        Icons.add_photo_alternate,
                        color: AppColors.solar,
                      ),
                      label: isProcessing ? '분석 중' : '사진 등록',
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _TabNavigator extends StatelessWidget {
  const _TabNavigator({
    required this.navigatorKey,
    required this.child,
  });

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
