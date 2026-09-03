import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../catalog/viewmodel/catalog_view_model.dart';
import '../../gallery/viewmodel/gallery_view_model.dart';
import '../../home/viewmodel/home_view_model.dart';
import '../../light_pollution_map/viewmodel/light_pollution_map_view_model.dart';
import '../../settings/viewmodel/equipment_view_model.dart';
import '../../settings/viewmodel/settings_view_model.dart';
import '../../sky_map/viewmodel/sky_map_view_model.dart';
import '../../stats/viewmodel/stats_view_model.dart';
import '../../../services/api_key_service.dart';
import '../../../services/base_exposure_settings_service.dart';
import '../../../services/recommendation_settings_service.dart';
import '../../../services/splash_image_service.dart';
import '../models/startup_step.dart';
import '../splash_frame_yield.dart';

/// 앱 시작 시 주요 ViewModel/설정을 단계적으로 preload한다.
class AppStartupViewModel extends ChangeNotifier {
  AppStartupViewModel({
    required ApiKeyService apiKeyService,
    required SettingsViewModel settingsViewModel,
    required EquipmentViewModel equipmentViewModel,
    required RecommendationSettingsService recommendationSettingsService,
    required BaseExposureSettingsService baseExposureSettingsService,
    required HomeViewModel homeViewModel,
    required CatalogViewModel catalogViewModel,
    required GalleryViewModel galleryViewModel,
    required StatsViewModel statsViewModel,
    required SkyMapViewModel skyMapViewModel,
    required LightPollutionMapViewModel lightPollutionMapViewModel,
    SplashImageService? splashImageService,
  }) : _apiKeyService = apiKeyService,
       _equipmentViewModel = equipmentViewModel,
       _recommendationSettingsService = recommendationSettingsService,
       _baseExposureSettingsService = baseExposureSettingsService,
       _homeViewModel = homeViewModel,
       _catalogViewModel = catalogViewModel,
       _galleryViewModel = galleryViewModel,
       _statsViewModel = statsViewModel,
       _skyMapViewModel = skyMapViewModel,
       _lightPollutionMapViewModel = lightPollutionMapViewModel,
       _splashImageService = splashImageService ?? SplashImageService();

  /// 브랜드 Splash 최소 표시 시간 — 홈 무거운 작업이 끝난 뒤에도
  /// 너무 짧게 깜빡이지 않도록 여유를 둔다.
  static const minDisplayDuration = Duration(milliseconds: 3200);

  final ApiKeyService _apiKeyService;
  final EquipmentViewModel _equipmentViewModel;
  final RecommendationSettingsService _recommendationSettingsService;
  final BaseExposureSettingsService _baseExposureSettingsService;
  final HomeViewModel _homeViewModel;
  final CatalogViewModel _catalogViewModel;
  final GalleryViewModel _galleryViewModel;
  final StatsViewModel _statsViewModel;
  final SkyMapViewModel _skyMapViewModel;
  final LightPollutionMapViewModel _lightPollutionMapViewModel;
  final SplashImageService _splashImageService;

  List<StartupStep> _steps = const [
    StartupStep(id: 'api', label: 'API 설정'),
    StartupStep(id: 'settings', label: '환경설정'),
    StartupStep(id: 'catalog', label: 'Catalog'),
    StartupStep(id: 'equipment', label: '장비 정보'),
    StartupStep(id: 'favorites', label: '즐겨찾기'),
    StartupStep(id: 'home', label: '홈 화면'),
  ];

  String _tagline = '밤하늘을 준비하고 있습니다.';
  bool _isReady = false;
  bool _isRunning = false;
  String? _errorMessage;

  List<StartupStep> get steps => _steps;
  String get tagline => _tagline;
  bool get isReady => _isReady;
  String? get errorMessage => _errorMessage;

  /// Windows의 첫 화면은 사진 등록 작업공간이다. 추천 전체 계산과
  /// 카탈로그 보조 인덱스는 첫 화면을 그리는 데 필요하지 않으므로,
  /// 모바일과 달리 Splash를 막지 않고 해당 화면이 필요할 때 준비한다.
  bool get _deferSecondaryWorkForWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> run() async {
    if (_isRunning || _isReady) return;
    _isRunning = true;
    _errorMessage = null;
    final startedAt = DateTime.now();

    // VisualLayer와 병렬로 누락 Splash 이미지를 채운다 (UI 블로킹 없음).
    unawaited(_splashImageService.ensureCached());

    try {
      await _runStep(
        id: 'api',
        tagline: '관측 환경을 준비하는 중...',
        action: () async {
          // Maps and backend credentials are supplied by the application build.
          // Startup must not depend on values left in device SecureStorage.
          await _apiKeyService.clearLegacyCredentials();
        },
      );

      await _runStep(
        id: 'settings',
        tagline: '환경설정을 불러오는 중...',
        action: () async {
          await Future.wait([
            _recommendationSettingsService.load(),
            _baseExposureSettingsService.load(),
          ]);
        },
      );

      await _runStep(
        id: 'catalog',
        tagline: '메시에 카탈로그를 준비하는 중...',
        // 검색 인덱스·장비 칩은 목록 로드 후 백그라운드에서 이어서 구축
        action: () => _catalogViewModel.load(deferHeavyWork: true),
      );

      await _runStep(
        id: 'equipment',
        tagline: '장비 정보를 불러오는 중...',
        action: () => _equipmentViewModel.load(),
      );

      await _runStep(
        id: 'favorites',
        tagline: '별자리 데이터를 초기화하는 중...',
        action: () => _lightPollutionMapViewModel.loadFavorites(),
      );

      await _runStep(
        id: 'home',
        tagline: '오늘 관측 정보를 준비하는 중...',
        // 목록만 먼저 로드하고, 추천 등 무거운 작업은 바로 아래에서 완료한다.
        action: () => _homeViewModel.load(deferHeavyWork: true),
      );

      if (_deferSecondaryWorkForWindows) {
        // Windows는 첫 진입이 사진 등록이므로 아래 두 작업을 기다릴
        // 이유가 없다. RecommendationEngine의 전체 Catalog 순회와
        // 검색 인덱스/장비 chip 구축은 해당 기능을 여는 시점에 수행한다.
        _tagline = '사진 등록 화면을 준비하는 중...';
        notifyListeners();
        await yieldForSplashAnimation();
      } else {
        // 모바일 홈은 진입 직후 추천을 표시하므로 기존처럼 준비를 완료한다.
        _tagline = '추천 대상을 계산하는 중...';
        notifyListeners();
        await yieldForSplashAnimation();
        try {
          await _homeViewModel.finishDeferredHeavyWork();
          await yieldForSplashAnimation();
          await _catalogViewModel.finishDeferredHeavyWork();
          await yieldForSplashAnimation();
        } catch (_) {
          // 실패해도 메인은 진입 — 탭에서 재시도
        }
      }

      PaintingBinding.instance.imageCache.maximumSize = 240;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 96 << 20;
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      _tagline = '시작 준비 중 문제가 발생했습니다.';
      notifyListeners();
    }

    // max(실제 초기화, 최소 표시)
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < minDisplayDuration) {
      await Future<void>.delayed(minDisplayDuration - elapsed);
    }

    _tagline = '오늘도 맑은 하늘이 되길 바랍니다.';
    _isReady = true;
    _isRunning = false;
    notifyListeners();

    // Windows의 첫 화면은 사진 등록이며 부가 탭은 선택 시 lazy load한다.
    // 모바일은 기존 워밍업 동작을 그대로 유지한다.
    if (!_deferSecondaryWorkForWindows) {
      unawaited(_warmSecondaryTabs());
    }
  }

  Future<void> _warmSecondaryTabs() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    try {
      if (!_galleryViewModel.hasLoaded) {
        await _galleryViewModel.load(silent: true);
        await yieldForSplashAnimation();
      }
      if (!_statsViewModel.hasLoaded) {
        await _statsViewModel.load();
        await yieldForSplashAnimation();
      }
      if (!_skyMapViewModel.hasLoaded) {
        await _skyMapViewModel.load();
      }
    } catch (_) {
      // 워밍 실패는 탭 진입 시 재시도
    }
  }

  Future<void> _runStep({
    required String id,
    required String tagline,
    required Future<void> Function() action,
  }) async {
    _tagline = tagline;
    await _setStatus(id, StartupStepStatus.loading);
    await yieldForSplashAnimation();
    try {
      await action();
      await _setStatus(id, StartupStepStatus.done);
      await yieldForSplashAnimation();
    } catch (error) {
      await _setStatus(id, StartupStepStatus.error);
      // 개별 단계 실패는 기록만 하고 다음 단계를 계속 진행한다.
      _errorMessage ??= error.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      await yieldForSplashAnimation();
    }
  }

  Future<void> _setStatus(String id, StartupStepStatus status) async {
    _steps = [
      for (final step in _steps)
        if (step.id == id) step.copyWith(status: status) else step,
    ];
    notifyListeners();
  }
}
