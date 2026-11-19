import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/di/app_providers.dart';
import 'core/theme/app_theme.dart';
import 'data/models/tc_backend_models.dart';
import 'features/catalog/viewmodel/catalog_view_model.dart';
import 'features/gallery/viewmodel/gallery_view_model.dart';
import 'features/home/viewmodel/home_view_model.dart';
import 'features/light_pollution_map/viewmodel/light_pollution_map_view_model.dart';
import 'features/settings/viewmodel/equipment_view_model.dart';
import 'features/settings/viewmodel/settings_view_model.dart';
import 'features/sky_map/viewmodel/sky_map_view_model.dart';
import 'features/splash/view/astro_splash_screen.dart';
import 'features/splash/viewmodel/app_startup_view_model.dart';
import 'features/stats/viewmodel/stats_view_model.dart';
import 'services/api_key_service.dart';
import 'services/base_exposure_settings_service.dart';
import 'services/catalog_favorite_controller.dart';
import 'services/recommendation_settings_service.dart';
import 'services/splash_image_service.dart';
import 'services/tc_backend_startup_resume_service.dart';
import 'services/tc_backend_connection_manager.dart';
import 'services/gallery_incremental_refresh_service.dart';
import 'shared/widgets/main_shell.dart';
import 'shared/widgets/pc_main_shell.dart';

class AstroJournalApp extends StatelessWidget {
  const AstroJournalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: AppProviders.build(context),
      child: const _BackendConnectionLifecycle(),
    );
  }
}

class _BackendConnectionLifecycle extends StatefulWidget {
  const _BackendConnectionLifecycle();

  @override
  State<_BackendConnectionLifecycle> createState() =>
      _BackendConnectionLifecycleState();
}

class _BackendConnectionLifecycleState
    extends State<_BackendConnectionLifecycle>
    with WidgetsBindingObserver {
  late final TcBackendConnectionManager _connectionManager;
  late final CatalogFavoriteController _catalogFavorites;
  Timer? _favoritesRefreshTimer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectionManager = context.read<TcBackendConnectionManager>();
    _catalogFavorites = context.read<CatalogFavoriteController>();
    unawaited(_catalogFavorites.restoreCache());
    _connectionManager.addListener(_refreshFavoritesWhenConnected);
    _connectionManager.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _connectionManager.resume();
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          unawaited(_refreshGalleryAfterResume());
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _foreground = false;
        _favoritesRefreshTimer?.cancel();
        _favoritesRefreshTimer = null;
        unawaited(_connectionManager.pause());
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _startFavoritesRefreshTimer() {
    _favoritesRefreshTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshFavoritesWhenConnected(),
    );
  }

  void _refreshFavoritesWhenConnected() {
    final status = _connectionManager.status;
    if (_foreground &&
        (status == TcBackendConnectionStatus.connected ||
            status == TcBackendConnectionStatus.degraded)) {
      _startFavoritesRefreshTimer();
      unawaited(_catalogFavorites.initialize());
    }
  }

  Future<void> _refreshGalleryAfterResume() async {
    try {
      await _connectionManager.reconnect();
      if (!mounted) return;
      await context.read<GalleryIncrementalRefreshService>().refresh();
    } catch (error) {
      debugPrint('Gallery foreground refresh skipped: $error');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _favoritesRefreshTimer?.cancel();
    _connectionManager.removeListener(_refreshFavoritesWhenConnected);
    _connectionManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '천체 기록장',
    debugShowCheckedModeBanner: false,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ko', 'KR'), Locale('en')],
    theme: AppTheme.dark,
    home: const _AppStartupGate(),
  );
}

/// Provider 준비 후 주요 데이터를 preload하고, 완료되면 플랫폼 Shell로 페이드 진입한다.
class _AppStartupGate extends StatefulWidget {
  const _AppStartupGate();

  @override
  State<_AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<_AppStartupGate> {
  late final AppStartupViewModel _startup;
  var _showMain = false;

  @override
  void initState() {
    super.initState();
    _startup = AppStartupViewModel(
      apiKeyService: context.read<ApiKeyService>(),
      settingsViewModel: context.read<SettingsViewModel>(),
      equipmentViewModel: context.read<EquipmentViewModel>(),
      recommendationSettingsService: context
          .read<RecommendationSettingsService>(),
      baseExposureSettingsService: context.read<BaseExposureSettingsService>(),
      homeViewModel: context.read<HomeViewModel>(),
      catalogViewModel: context.read<CatalogViewModel>(),
      galleryViewModel: context.read<GalleryViewModel>(),
      statsViewModel: context.read<StatsViewModel>(),
      skyMapViewModel: context.read<SkyMapViewModel>(),
      lightPollutionMapViewModel: context.read<LightPollutionMapViewModel>(),
      splashImageService: context.read<SplashImageService>(),
    );
    _startup.addListener(_onStartupChanged);
    _startup.run();
    unawaited(_resumeBackend());
  }

  Future<void> _resumeBackend() async {
    await context.read<TcBackendConnectionManager>().reconnect();
    if (!mounted) return;
    await context.read<TcBackendStartupResumeService>().resume();
  }

  void _onStartupChanged() {
    // 단계 갱신은 LoadingLayer만 처리. 준비 완료 시에만 Main으로 페이드.
    if (_startup.isReady && mounted && !_showMain) {
      setState(() => _showMain = true);
    }
  }

  @override
  void dispose() {
    _startup.removeListener(_onStartupChanged);
    _startup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: _showMain
          ? _mainShell()
          : AstroSplashScreen(
              key: const ValueKey<String>('astro_splash'),
              startup: _startup,
              splashImageService: context.read<SplashImageService>(),
            ),
    );
  }

  Widget _mainShell() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return const PcMainShell(key: ValueKey<String>('pc_main_shell'));
    }
    return const MainShell(key: ValueKey<String>('main_shell'));
  }
}
